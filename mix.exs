defmodule Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp aliases do
    [
      "deps.get.all": ["deps.get"],
      "app.setup": [
        "do --app core ecto.create",
        "do --app core ecto.migrate",
        "do --app core run apps/core/priv/repo/seeds.exs",
        "do --app public assets.setup",
        "do --app admin assets.setup"
      ],
      "app.build": [
        "do --app public assets.build",
        "do --app admin assets.build"
      ],
      setup: ["deps.get.all", "app.setup", "app.build"],
      "ecto.setup": [
        "do --app core ecto.create",
        "do --app core ecto.migrate",
        "do --app core run apps/core/priv/repo/seeds.exs"
      ],
      "ecto.reset": ["do --app core ecto.drop", "do --app core ecto.create", "do --app core ecto.migrate", "do --app core core.seed"],
      seed: ["do --app core core.seed"],
      "public.server": ["do --app public phx.server"],
      "admin.server": ["do --app admin phx.server"],
      run: ["public.server", "admin.server"],
      "assets.setup": [
        "do --app public assets.setup",
        "do --app admin assets.setup"
      ],
      "assets.build": [
        "do --app public assets.build",
        "do --app admin assets.build"
      ],
      "assets.deploy": [
        "do --app public assets.deploy",
        "do --app admin assets.deploy"
      ]
    ]
  end

  defp deps do
    []
  end
end
