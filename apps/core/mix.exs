defmodule Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Core.Application, []}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.0-rc.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:dns_cluster, "~> 0.1.1"},
      {:bcrypt_elixir, "~> 3.0"},
      {:swoosh, "~> 1.16"},
      {:finch, "~> 0.13"},
      {:jason, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:let_me, "~> 1.2.5"},
      {:stripity_stripe, "~> 2.0"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.6"},
      {:resend, "~> 0.4.0"},
      {:premailex, "~> 0.3.20"},
      {:mdex, "~> 0.7.0"},
      {:anthropix, "~> 0.6.1"},
      {:openai_ex, "~> 0.9.12"},
      {:faker, "~> 0.18.0", only: [:dev, :test]},
      {:tidewave, "~> 0.1", only: :dev},
    ]
  end
end
