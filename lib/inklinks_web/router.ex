defmodule InklinksWeb.Router do
  use InklinksWeb, :router

  import Dstar.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug InklinksWeb.Plugs.ReaderId
    plug :put_root_layout, html: {InklinksWeb.Layouts, :root}
    # Datastar sends the CSRF token as the `csrf` signal; this copies it to
    # where Plug.CSRFProtection looks. It must come first.
    plug Dstar.Plugs.RenameCsrfParam
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"referrer-policy" => "no-referrer"}
  end

  scope "/", InklinksWeb do
    pipe_through :browser

    get "/", LibraryController, :index
    post "/inklinks/:inklink_id/readings", ReadingController, :create
    dstar("/readings/:id", ReadingPage)
  end
end
