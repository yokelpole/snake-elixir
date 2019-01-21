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

    obstacles = mySnakeNoTail["body"] ++ Enum.flat_map(otherSnakesNoTail, fn x -> x["body"] end)

    possibleDirections = obstacle_check(
      List.first(mySnakeNoTail["body"]),
      obstacles,
      board["board"]["height"],
      board["board"]["width"]
    )

    food_incentive(mySnakeNoTail, obstacles, board["board"]["food"])

    %{
      move: Enum.max_by(possibleDirections, fn {_,y} -> y end) |> Kernel.elem(0) |> Atom.to_string,
    }
  end

  def food_incentive(snake, obstacles, food) do
    # Keep snake away from food if not hungry enough.
    # Make snake go for food if it is under hunger level.
    incentive = if (snake["hungry"] > 70), do: +25, else: -25
    snake_head = List.first(snake["body"])

    # Find the closest food that isn't blocked by a snake.
    closestFood = Enum.map(
      food,
      fn coord -> Map.merge(
        coord,
        %{"x_travel" => abs(snake_head["x"] - coord["x"]), "y_travel" => abs(snake_head["y"] - coord["y"])})
      end
    )

    # Eliminate food that has a snake in the way.
    IO.inspect(closestFood)
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
