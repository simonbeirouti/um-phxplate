defmodule Core.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Core.Repo,
      {DNSCluster, query: Application.get_env(:core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Core.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Core.Finch},
      # Start a worker by calling: Core.Worker.start_link(arg)
      # {Core.Worker, arg},
      # AI Evaluation Queue - add before the endpoint
      {Core.AI.EvaluationQueue, []},
      # Add a Task supervisor for potentially long-running tasks
      {Task.Supervisor, name: Core.TaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Core.Supervisor]
    result = Supervisor.start_link(children, opts)

    result
  end
end
