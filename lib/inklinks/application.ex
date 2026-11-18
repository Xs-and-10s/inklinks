defmodule Inklinks.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      InklinksWeb.Telemetry,
      Inklinks.Repo,
      Inklinks.Stories,
      {Phoenix.PubSub, name: Inklinks.PubSub},
      # Start a worker by calling: Inklinks.Worker.start_link(arg)
      # {Inklinks.Worker, arg},
      # Start to serve requests, typically the last entry
      InklinksWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Inklinks.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    InklinksWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
