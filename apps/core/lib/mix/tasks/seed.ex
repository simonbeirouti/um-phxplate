defmodule Mix.Tasks.Core.Seed do
  @moduledoc """
  Runs the Core app seeds without starting web servers.
  """
  use Mix.Task

  @shortdoc "Run Core app seeds"

  def run(_) do
    # Start only the essential applications for Ecto and HTTP requests
    Mix.Task.run("app.config", [])
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:hackney)
    {:ok, _} = Application.ensure_all_started(:jason)
    {:ok, _} = Application.ensure_all_started(:stripity_stripe)
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

    # Start the Core.Repo and PubSub without the full application
    {:ok, _} = Core.Repo.start_link()
    {:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: Core.PubSub}], strategy: :one_for_one)

    # Change to Core app directory and run seeds
    core_dir = Path.join([File.cwd!(), "apps", "core"])
    File.cd!(core_dir)
    Code.eval_file("priv/repo/seeds.exs")

    IO.puts("✅ Seeds completed successfully!")
  end
end
