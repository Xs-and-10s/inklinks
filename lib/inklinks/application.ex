defmodule Inklinks.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        InklinksWeb.Telemetry,
        Inklinks.Repo,
        Inklinks.Stories,
        {Phoenix.PubSub, name: Inklinks.PubSub},
        InklinksWeb.Endpoint
      ] ++ sweeper()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Inklinks.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Infers abandoned readings; off in tests, which sweep by hand.
  defp sweeper do
    case Application.get_env(:inklinks, :sweep_every, :timer.minutes(10)) do
      nil -> []
      every -> [{Inklinks.Abandonment.Sweeper, every}]
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    InklinksWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
