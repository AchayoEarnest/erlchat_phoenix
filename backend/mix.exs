defmodule Chat.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat,
      version: "1.0.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      mod: {Chat.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix core
      {:phoenix, "~> 1.7.12"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_live_dashboard, "~> 0.8.3"},

      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},

      # HTTP server
      {:bandit, "~> 1.5"},

      # Auth
      {:bcrypt_elixir, "~> 3.1"},
      {:joken, "~> 2.6"},

      # JSON
      {:jason, "~> 1.4"},

      # File uploads
      {:plug_cowboy, "~> 2.7"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.20"},
      {:sweet_xml, "~> 0.7"},

      # Redis (optional pub/sub for multi-node)
      {:redix, "~> 1.5"},

      # Utilities
      {:ecto_psql_extras, "~> 0.8"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},

      # Dev / test
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
