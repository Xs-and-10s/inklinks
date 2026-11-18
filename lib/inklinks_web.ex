defmodule InklinksWeb do
  @moduledoc """
  The entrypoint for the web interface: `use InklinksWeb, :controller`,
  `use InklinksWeb, :html`, and so on.

  There is no LiveView here. Pages are plain HTTP: a GET renders HTML, and
  Datastar sends commands back as POSTs that answer with server-sent events
  (see `Dstar`). HEEx comes from `phoenix_live_view`, which is why that
  dependency stays.
  """

  def static_paths, do: ~w(assets vendor favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      import Phoenix.HTML

      alias InklinksWeb.Layouts

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: InklinksWeb.Endpoint,
        router: InklinksWeb.Router,
        statics: InklinksWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
