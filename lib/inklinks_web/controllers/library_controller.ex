defmodule InklinksWeb.LibraryController do
  use InklinksWeb, :controller

  alias Inklinks.Catalog

  def index(conn, _params) do
    render(conn, :index, page_title: "Library", inklinks: Catalog.list())
  end
end
