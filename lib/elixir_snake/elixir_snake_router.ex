defmodule ElixirSnake.Router do
  use Plug.Router
  use Plug.Debugger
  require Logger

  plug(Plug.Logger, log: :debug)

  plug(:match)
  plug(:dispatch)

  # Routes!
  get "/" do
    send_resp(conn, 200, "This is the home of a battlesnake built with Elixir, please visit battlesnake.io")
  end

  post "/start" do
    {:ok, body, conn} = read_body(conn)
    body = Poison.decode!(body)
    IO.inspect(body)
    send_resp(conn, 200, "")
  end

  post "/move" do
    {:ok, body, conn} = read_body(conn)
    body = Poison.decode!(body)
    IO.inspect(body)
    send_resp(conn, 200, "move")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
