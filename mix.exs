defmodule ElixirSnake.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_snake,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :cowboy, :plug, :poison],
      mod: {ElixirSnake.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cowboy, "~> 2.5"},
      {:plug, "~> 1.6"},
      {:poison, "~> 4.0"},
      {:exprof, "~> 0.2.0"}
    ]
  end
end
