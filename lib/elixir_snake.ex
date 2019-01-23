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

    mySnakeNoTail = Map.put(
      board["you"],
      "body",
      Enum.drop(board["you"]["body"], -1)
    )

    otherSnakesNoTail = Enum.map(
      Enum.reject(board["board"]["snakes"], fn x -> myId == x["id"] end),
      fn x -> Map.put(x, "body", Enum.drop(x["body"], -1)) end
    )

    # Own head is not an obstacle
    obstacles = List.delete_at(mySnakeNoTail["body"], 0) ++ Enum.flat_map(otherSnakesNoTail, fn x -> x["body"] end)

    possibleDirections = obstacle_check(
      List.first(mySnakeNoTail["body"]),
      obstacles,
      board["board"]["height"],
      board["board"]["width"]
    ) |> Keyword.merge(foodIncentive(mySnakeNoTail, obstacles, board["board"]["food"]), fn _, v1, v2 -> v1 + v2 end)

    %{
      move: Enum.max_by(possibleDirections, fn {_,y} -> y end) |> Kernel.elem(0) |> Atom.to_string,
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

  def foodIncentive(snake, obstacles, food) do
    # Keep snake away from food if not hungry enough.
    # Make snake go for food if it is under hunger level.
    hungry = snake["health"] < 70
    snake_head = List.first(snake["body"])

    # Find the closest food that isn't blocked by a snake.
    closestFood = Enum.map(
      food,
      fn coord -> Map.merge(
        coord,
        %{"total_travel" => abs(snake_head["x"] - coord["x"]) + abs(snake_head["y"] - coord["y"])})
      end
    ) |> Enum.sort(&(&1["total_travel"] < &2["total_travel"]))
      |> Enum.filter(fn food -> is_clear_path(snake_head, obstacles, food) end)
      |> List.first

    IO.inspect(closestFood)

    cond do
      hungry && snake_head["x"] == closestFood["x"] && snake_head["y"] < closestFood["y"] -> [up: 0.25]
      hungry && snake_head["x"] == closestFood["x"] && snake_head["y"] > closestFood["y"] -> [down: 0.25]
      hungry && snake_head["y"] == closestFood["y"] && snake_head["x"] < closestFood["x"] -> [right: 0.25]
      hungry && snake_head["y"] == closestFood["y"] && snake_head["x"] > closestFood["x"] -> [left: 0.25]
      true -> []
    end
  end

  def obstacle_check(snake_head, obstacles, board_height, board_width) do
    boardLimits = Keyword.merge(
      cond do
        snake_head["x"] - 1 < 0 -> [left: -1]
        snake_head["x"] + 1 == board_width -> [right: -1]
        true -> []
      end,
      cond do
        snake_head["y"] - 1 < 0 -> [up: -1]
        snake_head["y"] + 1 == board_height -> [down: -1]
        true -> []
      end
    )

    immediateObstacles = Enum.map(
      obstacles,
      fn coord ->
        cond do
          snake_head == %{coord | "x" => coord["x"] + 1} -> [left: -1]
          snake_head == %{coord | "y" => coord["y"] + 1} -> [up: -1]
          snake_head == %{coord | "x" => coord["x"] - 1} -> [right: -1]
          snake_head == %{coord | "y" => coord["y"] - 1} -> [down: -1]
          true -> []
        end
      end
    ) |> List.flatten

    Keyword.new([up: 1.5, right: 1.5, down: 1.5, left: 1.5]) |>
      Keyword.merge(boardLimits, fn _, v1, v2 -> v1 + v2 end) |>
      Keyword.merge(immediateObstacles, fn _, v1, v2 -> v1 + v2 end)
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
