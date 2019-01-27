defmodule ElixirSnake do
  @moduledoc """
  This is where you define the logic of your battlesnake!
  """

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

  @doc """
    This is the response to Post /move
    Your snake logic should live here
  """
  def move_resp(board) do
    IO.inspect(board)

    myId = board["you"]["id"]

    my_snake_no_tail = Map.put(
      board["you"],
      "body",
      Enum.drop(board["you"]["body"], -1)
    )

    other_snakes_no_tail = Enum.map(
      Enum.reject(board["board"]["snakes"], fn x -> myId == x["id"] end),
      fn x -> Map.put(x, "body", Enum.drop(x["body"], -1)) end
    )

    board_map = get_board(
      my_snake_no_tail,
      other_snakes_no_tail,
      board["board"]["food"],
      board["board"]["height"],
      board["board"]["width"]
    )

    %{ move: get_direction(
        List.first(my_snake_no_tail["body"]),
        board_map,
        board["board"]["height"],
        board["board"]["width"]
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
    snake_body_val = -5.00
    open_space_val = 0.5
    food_incentive = if own_snake["health"] < 70, do: +5.00, else: -0.33
    attack_incentive = 2.5
    defend_incentive = -1.0
    # TODO: Implement attack/dodge incentive.
    # TODO: All of the keys being strings rather than {0, 1} values may be clumsy.

    # generate keys to be used in board object.
    calc_row = fn(row, row_length) -> Enum.map(0..row_length, fn x -> { row, x } end) end
    keys = Enum.flat_map(0..board_width, fn x -> calc_row.(x, board_height) end)

    # Make an empty board with all types set to free.
    empty_board = Enum.flat_map(
      keys,
      fn coord -> %{ coord => %{"type" => "free", "value" => open_space_val }} end
    ) |> Map.new

    # Place the user snake on the board.
    # TODO: Do we need to have an own_snake type?
    own_snake_map = Enum.flat_map(
      own_snake["body"],
      fn coord ->
        %{{ coord["x"],coord["y"] } => %{
          "type" => "own_snake_body",
          "value" => snake_body_val
        }}
      end
    ) |> Map.new

    # Place other snakes on the board.
    other_snake_map = Enum.flat_map(
      other_snakes,
      fn snake -> Enum.flat_map(
        snake["body"],
        fn coord ->
          %{{ coord["x"],coord["y"] } => %{
            "type" => "snake_body",
            "value" => snake_body_val
          }}
        end
      ) end
    ) |> Map.new

    other_snake_heads = Enum.flat_map(
      other_snakes,
      fn snake ->
        coord = List.first(snake["body"])
        %{ { coord["x"],coord["y"] } => %{
          "type" => "snake_head",
          "value" => if(own_snake["health"] > snake["health"], do: attack_incentive, else: defend_incentive)
        }}
      end
    ) |> Map.new

    food_map = Enum.flat_map(
      food,
      fn coord -> %{ { coord["x"],coord["y"] } => %{
        "type" => "food",
        "value" => food_incentive
      }} end
    ) |> Map.new

    Map.merge(empty_board, own_snake_map) |> Map.merge(other_snake_map) |> Map.merge(other_snake_heads) |> Map.merge(food_map)
  end

  def scan_sector(x, y, board_map, board_height, board_width, multiplier) do
    cond do
      multiplier < 0.25 -> board_map
      board_map[{x,y}]["scanned"] == true -> board_map
      (x < 0 || y < 0) || (x > board_width || y > board_height) ->
        Map.merge(board_map, %{ {x,y} => %{ "type" => "wall", "scanned" => true, "adjusted_value" => multiplier * -1.0 } })
      board_map[{x,y}]["type"] == "snake_body" || board_map[{x,y}]["type"] == "own_snake_body" -> (
        updated_sector = Map.merge(%{ "scanned" => true, "adjusted_value" => multiplier * -1.0 }, board_map[{ x,y }])
        Map.merge(board_map, %{ {x,y} => updated_sector })
      )
      true -> (
        updated_sector = Map.merge(%{ "scanned" => true, "adjusted_value" => board_map[{ x,y }]["value"] * multiplier }, board_map[{ x,y }])
        board_map = Map.merge(board_map, %{ {x,y} => updated_sector })

        # TODO: This feels wrong and I think there could be collisions on scanned sectors.
        take_scanned_sector = fn _, x, y ->
          cond do
            x["scanned"] && y["scanned"] && x["adjusted_value"] > y["adjusted_value"] -> x
            x["scanned"] && y["scanned"] && x["adjusted_value"] < y["adjusted_value"]-> y
            x["scanned"] -> x
            y["scanned"] -> y
            true -> y
          end
        end

        left_map = scan_sector(x - 1, y, board_map, board_height, board_width, multiplier - 0.05)
        board_map = Map.merge(board_map, left_map, take_scanned_sector)

        right_map = scan_sector(x + 1, y, board_map, board_height, board_width, multiplier - 0.05)
        board_map = Map.merge(board_map, right_map, take_scanned_sector)

        down_map = scan_sector(x, y + 1, board_map, board_height, board_width, multiplier - 0.05)
        board_map = Map.merge(board_map, down_map, take_scanned_sector)

        up_map = scan_sector(x, y - 1, board_map, board_height, board_width, multiplier - 0.05)
        board_map = Map.merge(board_map, up_map, take_scanned_sector)

        board_map
      )
    end
  end

  def get_direction(snake_head, board_map, board_height, board_width) do
    left_map = scan_sector(snake_head["x"] - 1, snake_head["y"], board_map, board_height, board_width, 1)
    right_map = scan_sector(snake_head["x"] + 1, snake_head["y"], board_map, board_height, board_width, 1)
    down_map = scan_sector(snake_head["x"], snake_head["y"] + 1, board_map, board_height, board_width, 1)
    up_map = scan_sector(snake_head["x"], snake_head["y"] - 1, board_map, board_height, board_width, 1)

    left_value = Enum.map(left_map, fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end) |> Enum.sum
    right_value = Enum.map(right_map, fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end) |> Enum.sum
    down_value = Enum.map(down_map, fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end) |> Enum.sum
    up_value = Enum.map(up_map, fn x -> x |> elem(1) end) |> Enum.map(fn x -> x["adjusted_value"] end) |> Enum.filter(fn x -> x != nil end) |> Enum.sum

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
