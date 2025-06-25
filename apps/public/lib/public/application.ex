defmodule Public.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Public.Telemetry,
      {Phoenix.PubSub, name: Public.PubSub},
      # Start a worker by calling: Public.Worker.start_link(arg)
      # {Public.Worker, arg},
      # Start to serve requests, typically the last entry
      Public.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Public.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Public.Endpoint.config_change(changed, removed)
    :ok
  end
end
