defmodule PhxplateUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      "deps.get.all": ["deps.get"],
      "app.setup": [
        "do --app core ecto.create",
        "do --app core ecto.migrate",
        "do --app core run apps/core/priv/repo/seeds.exs",
        "do --app web assets.setup",
        "do --app admin assets.setup"
      ],
      "app.build": [
        "do --app web assets.build",
        "do --app admin assets.build"
      ],
      setup: ["deps.get.all", "app.setup", "app.build"],
      "ecto.setup": [
        "do --app core ecto.create",
        "do --app core ecto.migrate",
        "do --app core run apps/core/priv/repo/seeds.exs"
      ],
      "ecto.reset": ["do --app core ecto.reset"],
      "web.server": ["do --app web phx.server"],
      "admin.server": ["do --app admin phx.server"],
      run: ["web.server", "admin.server"],
      test: ["test"],
      "assets.setup": [
        "do --app web assets.setup",
        "do --app admin assets.setup"
      ],
      "assets.build": [
        "do --app web assets.build",
        "do --app admin assets.build"
      ],
      "assets.deploy": [
        "do --app web assets.deploy",
        "do --app admin assets.deploy"
      ]
    ]
  end
end
