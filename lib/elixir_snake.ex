defmodule ElixirSnake do
  @moduledoc """
  This is where you define the logic of your battlesnake!
  """
  import ExProf.Macro

  @snake_hunger 70
  @multiplier_drop 0.70
  @multiplier_cut_off 0.10

  @snake_body_val -2
  @open_space_val 5
  @food_incentive 25.0
  @food_avoid_incentive -0.1
  @attack_incentive 5.0
  @defend_incentive -20.0
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
    base_board = board["board"]
    myId = board["you"]["id"]

    my_snake_no_tail = Map.put(
      board["you"],
      "body",
      Enum.drop(board["you"]["body"], -1)
    )

    other_snakes_no_tail = Enum.map(
      Enum.reject(base_board["snakes"], fn x -> myId == x["id"] end),
      fn x -> Map.put(x, "body", Enum.drop(x["body"], -1)) end
    )

    board_map = get_board(
      my_snake_no_tail,
      other_snakes_no_tail,
      base_board["food"],
      base_board["height"],
      base_board["width"]
    )

    IO.inspect("### MOVE # #{board["turn"]}")
    %{ move: get_direction(
        List.first(my_snake_no_tail["body"]),
        board_map,
        base_board["height"],
        base_board["width"]
      )
    }
  end

  def is_clear_path(current_coord, obstacles, end_coord) do
    # TODO: Check different directions to start to get to the food?
    # check if we have a collision, return false if so
    collisions = Enum.filter(obstacles, fn x -> x["x"] == current_coord["x"] && x["y"] == current_coord["y"] end)
    next_y_coord = if current_coord["y"] - end_coord["y"] < 0, do: current_coord["y"] + 1, else: current_coord["y"] - 1
    next_x_coord = if current_coord["x"] - end_coord["x"] < 0, do: current_coord["x"] + 1, else: current_coord["x"] - 1

    cond do
      current_coord["x"] == end_coord["x"] && current_coord["y"] == end_coord["y"] -> true
      current_coord["x"] == end_coord["x"] ->
        is_clear_path(
          %{current_coord | "y" => next_y_coord},
          obstacles,
          end_coord
        )
      Kernel.length(collisions) > 0 -> false
      true ->
        is_clear_path(
          %{current_coord | "x" => next_x_coord},
          obstacles,
          end_coord
        )
    end
  end

  def get_board(own_snake, other_snakes, food, board_height, board_width) do
    # TODO: Implement attack/dodge incentive.

    # generate keys to be used in board object.
    calc_row = fn(row, row_length) -> Enum.map(0..row_length, fn x -> { row, x } end) end
    keys = Enum.flat_map(0..board_width, fn x -> calc_row.(x, board_height) end)

    # Make an empty board with all types set to free.
    empty_board = Task.async(
      fn ->
        Enum.flat_map(
          keys,
          fn coord -> %{ coord => %{"type" => "free", "value" => @open_space_val }} end
        ) |> Map.new
      end
    )

    # Place the user snake on the board.
    # TODO: Do we need to have an own_snake type?
    own_snake_map = Task.async(
      fn ->
        Enum.flat_map(
          own_snake["body"],
          fn coord ->
            %{{ coord["x"],coord["y"] } => %{
              "type" => "own_snake_body",
              "value" => @snake_body_val
            }}
          end
        ) |> Map.new
      end
    )

    # Place other snakes on the board.
    other_snake_map = Task.async(
      fn ->
        Enum.flat_map(
          other_snakes,
          fn snake -> Enum.flat_map(
            snake["body"],
            fn coord ->
              %{{ coord["x"],coord["y"] } => %{
                "type" => "snake_body",
                "value" => @snake_body_val
              }}
            end
          ) end
        ) |> Map.new
      end
    )

    # TODO: We don't care where snake head is now, we care where it might be.
    other_snake_heads = Task.async(
      fn ->
        Enum.flat_map(
          other_snakes,
          fn snake ->
            coord = List.first(snake["body"])
            %{ { coord["x"],coord["y"] } => %{
              "type" => "snake_head",
              # TODO: Don't attack snake head
              # TODO: Use attack incentive
              "value" => if(own_snake["health"] >= snake["health"], do: @snake_body_val, else: @defend_incentive)
            }}
          end
        ) |> Map.new
      end
    )

    food_map = Task.async(
      fn ->
        Enum.flat_map(
          food,
          fn coord -> %{ { coord["x"],coord["y"] } => %{
            "type" => "food",
            "value" => if(own_snake["health"] < @snake_hunger, do: @food_incentive, else: @food_avoid_incentive)
          }} end
        ) |> Map.new
      end
    )

    Map.merge(Task.await(empty_board), Task.await(own_snake_map))
      |> Map.merge(Task.await(other_snake_map))
      |> Map.merge(Task.await(other_snake_heads))
      |> Map.merge(Task.await(food_map))
  end

  def apply_multiplier(value, multiplier) do
    value * multiplier
  end

  def scan_sector(x, y, board_map, board_height, board_width, multiplier) do
    target = board_map[{x,y}]
    out_of_bounds = ( x < 0 || y < 0) || (x >= board_width || y >= board_height )
    is_snake_body = target["type"] == "snake_body" || target["type"] == "own_snake_body"

    cond do
      multiplier < @multiplier_cut_off -> (
        board_map
      )
      target["scanned"] == true && target["adjusted_value"] > apply_multiplier(target["value"], multiplier) -> (
        board_map
      )
      out_of_bounds && multiplier == 1.0 -> (
        Map.put(board_map, {x,y}, %{ "type" => "wall", "scanned" => true, "adjusted_value" => @immediate_hard_object_score })
      )
      out_of_bounds -> (
        Map.put(board_map, {x,y}, %{ "type" => "wall", "scanned" => true, "adjusted_value" => apply_multiplier(@hard_object_score, multiplier) })
      )
      is_snake_body && multiplier == 1.0 -> (
        # Hack to keep snake from going back on itself when it doesn't like the nearby options.
        # Should put in something better, but the likelihood of -50 is low.
        Map.put(board_map, {x,y}, %{ "type" => "wall", "scanned" => true, "adjusted_value" => @immediate_hard_object_score })
      )
      is_snake_body -> (
        updated_sector = Map.merge(target, %{ "scanned" => true, "adjusted_value" => apply_multiplier(@hard_object_score, multiplier) })
        Map.put(board_map, {x,y}, updated_sector)
      )
      true -> (
        updated_sector = Map.merge(target, %{ "scanned" => true, "adjusted_value" => apply_multiplier(target["value"], multiplier) })
        updated_board_map = Map.put(board_map, {x,y}, updated_sector)

        # TODO: This feels wrong and I think there could be collisions on scanned sectors.
        take_scanned_sector = fn _, x, y ->
          both_scanned = x["scanned"] && y["scanned"]

          cond do
            both_scanned && x["adjusted_value"] > y["adjusted_value"] -> x
            both_scanned && x["adjusted_value"] < y["adjusted_value"] -> y
            x["scanned"] -> x
            y["scanned"] -> y
            true -> y
          end
        end

        left_map = Task.async(fn -> scan_sector(x - 1, y, updated_board_map, board_height, board_width, multiplier * @multiplier_drop) end)
        right_map = Task.async(fn -> scan_sector(x + 1, y, updated_board_map, board_height, board_width, multiplier * @multiplier_drop) end)
        down_map = Task.async(fn -> scan_sector(x, y + 1, updated_board_map, board_height, board_width, multiplier * @multiplier_drop) end)
        up_map = Task.async(fn -> scan_sector(x, y - 1, updated_board_map, board_height, board_width, multiplier * @multiplier_drop) end)

        Map.merge(Task.await(left_map), Task.await(right_map), take_scanned_sector)
          |> Map.merge(Task.await(down_map), take_scanned_sector)
          |> Map.merge(Task.await(up_map), take_scanned_sector)
      )
    end
  end

  def get_direction(snake_head, board_map, board_height, board_width) do

    left_map = Task.async(fn -> scan_sector(snake_head["x"] - 1, snake_head["y"], board_map, board_height, board_width, 1) end)
    right_map = Task.async(fn -> scan_sector(snake_head["x"] + 1, snake_head["y"], board_map, board_height, board_width, 1) end)
    down_map = Task.async(fn -> scan_sector(snake_head["x"], snake_head["y"] + 1, board_map, board_height, board_width, 1) end)
    up_map = Task.async(fn -> scan_sector(snake_head["x"], snake_head["y"] - 1, board_map, board_height, board_width, 1) end)

    left_valid = Enum.map(Task.await(left_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end)
    right_valid = Enum.map(Task.await(right_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end)
    down_valid = Enum.map(Task.await(down_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end)
    up_valid = Enum.map(Task.await(up_map), fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end)

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
