defmodule ElixirSnake do
  @moduledoc """
  This is where you define the logic of your battlesnake!
  """
  import ExProf.Macro

  @snake_hunger 70
  @multiplier_drop 0.70
  @multiplier_cut_off 0.10

  @snake_body_val -2
  @open_space_val 2.5
  @food_incentive 25.0
  @food_avoid_incentive -0.1
  @attack_incentive 5.0
  @defend_incentive -10.0
  @hard_object_score -2
  @immediate_hard_object_score -50.0

  @doc """
    This is the response to Post /start
    This is where you define your color
  """
  def start_resp(start_request) do
    IO.inspect(start_request)
    %{
      color: "#c0ffee",
      taunt: "I'm READY"
    }
  end

  @doc "get analysis records and sum them up"
  def do_profile(board) do
    {records, _block_result} = move_resp(board)
    total_percent = Enum.reduce(records, 0.0, &(&1.percent + &2))
    IO.inspect "total = #{total_percent}"
  end

  def profile_move_resp(board) do
    profile do
      move_resp(board)
    end
  end

  @doc """
    This is the response to Post /move
    Your snake logic should live here
  """
  def move_resp(board) do
    IO.inspect(board)
    %{ "board" => base_board, "you" => you } = board
    %{ "height" => height, "width" => width, "snakes" => snakes, "food" => food } = base_board
    %{ "body" => you_body, "id" => myId } = you

    my_snake_no_tail = Map.put(
      you,
      "body",
      if(Kernel.length(you_body) > 1, do: Enum.drop(you_body, -1), else: you_body)
    )
    %{ "body" => my_snake_no_tail_body } = my_snake_no_tail

    other_snakes_no_tail = Enum.map(
      Enum.reject(snakes, fn x -> myId == Map.fetch!(x, "id") end),
      fn x ->
        Map.put(
          x,
          "body",
          if(Kernel.length(Map.fetch!(x, "body")) > 1, do: Enum.drop(Map.fetch!(x, "body"), -1), else: Map.fetch!(x, "body"))
        )
      end
    )

    IO.inspect("### MOVE # #{board["turn"]}")
    %{ move:
        get_direction(
          List.first(my_snake_no_tail_body),
          get_board(
            my_snake_no_tail,
            other_snakes_no_tail,
            food,
            height,
            width
          ),
          height,
          width
        )
    }
  end

  def get_board(own_snake, other_snakes, food, board_height, board_width) do
    # TODO: Implement attack/dodge incentive.
    %{ "body" => own_snake_body, "health" => own_snake_health } = own_snake

    # generate keys to be used in board object.
    calc_row = fn(row, row_length) -> Enum.map(0..row_length, fn x -> { row, x } end) end
    keys = Enum.flat_map(0..board_width, fn x -> calc_row.(x, board_height) end)

    # Make an empty board with all types set to free.
    empty_board =
      Enum.flat_map(
        keys,
        fn coord -> %{ coord => %{
          "type" => "free",
          "value" => @open_space_val,
          "adjusted_value" => 0,
          "scanned" => false
        }} end
      ) |> Map.new

    # Place the user snake on the board.
    # TODO: Do we need to have an own_snake type?
    own_snake_map =
      Enum.flat_map(
        own_snake_body,
        fn coord ->
          %{ "x" => x, "y" => y } = coord
          %{{ x, y } => %{
            "type" => "own_snake_body",
            "value" => @snake_body_val,
            "adjusted_value" => 0,
            "scanned" => "false"
          }}
        end
      ) |> Map.new

    # Place other snakes on the board.
    other_snake_map =
      Enum.flat_map(
        other_snakes,
        fn snake -> Enum.flat_map(
          Map.fetch!(snake, "body"),
          fn coord ->
            %{ "x" => x, "y" => y } = coord
            %{ "health" => snake_health } = snake
            %{{ x, y } => %{
              "type" => "snake_body",
              "value" => if(own_snake_health >= snake_health, do: @snake_body_val, else: @defend_incentive),
              "adjusted_value" => 0,
              "scanned" => false
            }}
          end
        ) end
      ) |> Map.new

    # TODO: We don't care where snake head is now, we care where it might be.
    other_snake_heads =
      Enum.flat_map(
        other_snakes,
        fn snake ->
          coord = List.first(Map.fetch!(snake, "body"))
          %{ "x" => x, "y" => y } = coord
          %{ "health" => snake_health } = snake
          %{{ x, y } => %{
            "type" => "snake_head",
            # TODO: Don't attack snake head
            # TODO: Use attack incentive
            "value" => if(own_snake_health >= snake_health, do: @snake_body_val, else: @defend_incentive),
            "adjusted_value" => 0,
            "scanned" => false
          }}
        end
      ) |> Map.new

    food_map =
      Enum.flat_map(
        food,
        fn coord ->
          %{ "x" => x, "y" => y } = coord
          %{{ x, y } => %{
            "type" => "food",
            "value" => if(own_snake_health < @snake_hunger, do: @food_incentive, else: @food_avoid_incentive),
            "adjusted_value" => 0,
            "scanned" => false
          }
        } end
      ) |> Map.new

    Map.merge(empty_board, own_snake_map)
      |> Map.merge(other_snake_map)
      |> Map.merge(other_snake_heads)
      |> Map.merge(food_map)
  end

  def apply_multiplier(value, multiplier) do
    value * multiplier
  end

  def scan_sector(x, y, board_map, board_height, board_width, multiplier) do
    out_of_bounds = ( x < 0 || y < 0) || (x >= board_width || y >= board_height )

    if (out_of_bounds) do
      cond do
        out_of_bounds && multiplier == 1.0 -> (
          Map.put(board_map, {x,y}, %{ "type" => "wall", "scanned" => true, "adjusted_value" => @immediate_hard_object_score })
        )
        out_of_bounds -> (
          Map.put(board_map, {x,y}, %{ "type" => "wall", "scanned" => true, "adjusted_value" => apply_multiplier(@hard_object_score, multiplier) })
        )
      end
    else
      target = Map.fetch!(board_map, {x,y})
      %{ "scanned" => scanned, "adjusted_value" => adjusted_value, "type" => type, "value" => value } = target

      cond do
        multiplier < @multiplier_cut_off -> (
          board_map
        )
        scanned == true && adjusted_value > apply_multiplier(value, multiplier) -> (
          board_map
        )
        type == "snake_body" || type == "own_snake_body" && multiplier == 1.0 -> (
          # Hack to keep snake from going back on itself when it doesn't like the nearby options.
          # Should put in something better, but the likelihood of -50 is low.
          Map.put(board_map, {x,y}, %{ "type" => "wall", "scanned" => true, "adjusted_value" => @immediate_hard_object_score })
        )
        type == "snake_body" || type == "own_snake_body" -> (
          updated_sector = Map.merge(target, %{ "scanned" => true, "adjusted_value" => apply_multiplier(@hard_object_score, multiplier) })
          Map.put(board_map, {x,y}, updated_sector)
        )
        true -> (
          updated_sector = Map.merge(target, %{ "scanned" => true, "adjusted_value" => apply_multiplier(target["value"], multiplier) })
          updated_board_map = Map.put(board_map, {x,y}, updated_sector)

          # TODO: This feels wrong and I think there could be collisions on scanned sectors.
          take_scanned_sector = fn _, x, y ->
            %{ "scanned" => x_scanned } = x
            %{ "scanned" => y_scanned } = y

            if (x_scanned == true && y_scanned == true) do
              %{ "adjusted_value" => x_adjusted } = x
              %{ "adjusted_value" => y_adjusted } = y

              cond do
                x_adjusted > y_adjusted -> x
                x_adjusted < y_adjusted -> y
                true -> y
              end
            else
              cond do
                y_scanned -> y
                x_scanned -> x
                true -> y
              end
            end
          end

          left_map = Task.async(fn ->
            scan_sector(x - 1, y, updated_board_map, board_height, board_width, multiplier * @multiplier_drop)
              |> Enum.reject(fn val ->
                { {_, _ },%{ "adjusted_value" => adjusted_value } } = val
                adjusted_value == 0
              end)
              |> Map.new
          end)
          right_map = Task.async(fn ->
            scan_sector(x + 1, y, updated_board_map, board_height, board_width, multiplier * @multiplier_drop)
              |> Enum.reject(fn val ->
                { {_, _ },%{ "adjusted_value" => adjusted_value } } = val
                adjusted_value == 0
              end)
              |> Map.new
          end)
          down_map = Task.async(fn ->
            scan_sector(x, y + 1, updated_board_map, board_height, board_width, multiplier * @multiplier_drop)
              |> Enum.reject(fn val ->
                { {_, _ },%{ "adjusted_value" => adjusted_value } } = val
                adjusted_value == 0
              end)
              |> Map.new
          end)
          up_map = Task.async(fn ->
            scan_sector(x, y - 1, updated_board_map, board_height, board_width, multiplier * @multiplier_drop)
              |> Enum.reject(fn val ->
                { {_, _ },%{ "adjusted_value" => adjusted_value } } = val
                adjusted_value == 0
              end)
              |> Map.new
          end)

          Map.merge(Task.await(left_map), Task.await(right_map), take_scanned_sector)
            |> Map.merge(Task.await(down_map), take_scanned_sector)
            |> Map.merge(Task.await(up_map), take_scanned_sector)
        )
      end
    end
  end

  def get_direction(snake_head, board_map, board_height, board_width) do
    %{ "x" => snake_head_x, "y" => snake_head_y } = snake_head

    left_map = Task.async(fn -> scan_sector(snake_head_x - 1, snake_head_y, board_map, board_height, board_width, 1) end)
    right_map = Task.async(fn -> scan_sector(snake_head_x + 1, snake_head_y, board_map, board_height, board_width, 1) end)
    down_map = Task.async(fn -> scan_sector(snake_head_x, snake_head_y + 1, board_map, board_height, board_width, 1) end)
    up_map = Task.async(fn -> scan_sector(snake_head_x, snake_head_y - 1, board_map, board_height, board_width, 1) end)

    left_valid = Enum.map(Task.await(left_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> Map.get(x, "adjusted_value") end) |> Enum.filter(fn x -> x != 0 end)
    right_valid = Enum.map(Task.await(right_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> Map.get(x, "adjusted_value") end) |> Enum.filter(fn x -> x != 0 end)
    down_valid = Enum.map(Task.await(down_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> Map.get(x, "adjusted_value") end) |> Enum.filter(fn x -> x != 0 end)
    up_valid = Enum.map(Task.await(up_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> Map.get(x, "adjusted_value") end) |> Enum.filter(fn x -> x != 0 end)

    left_value = Enum.sum(left_valid) #/ Kernel.length(left_valid)
    right_value =  Enum.sum(right_valid) #/ Kernel.length(right_valid)
    down_value =  Enum.sum(down_valid) #/ Kernel.length(down_valid)
    up_value =  Enum.sum(up_valid) #/ Kernel.length(up_valid)

    IO.inspect("### NUMBER OF DATA POINTS FOR LEFT #{Kernel.length(left_valid)}")
    IO.inspect("### NUMBER OF DATA POINTS FOR RIGHT #{Kernel.length(right_valid)}")
    IO.inspect("### NUMBER OF DATA POINTS FOR DOWN #{Kernel.length(down_valid)}")
    IO.inspect("### NUMBER OF DATA POINTS FOR UP #{Kernel.length(up_valid)}")

    # TODO: Give weight to the # of data points gathered.

    directions = %{ left: left_value, right: right_value, down: down_value, up: up_value }

    IO.inspect(directions)
    Enum.max_by(directions, fn {_,y} -> y end) |> Kernel.elem(0) |> Atom.to_string
  end

  @doc """
    This is the response to Post /end
    This does not need to do anything
  """
  def end_resp(end_request) do
    IO.inspect(end_request)
    %{}
  end
end
