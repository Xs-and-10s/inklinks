defmodule InklinksWeb.LibraryController do
  use InklinksWeb, :controller

  alias Inklinks.{Catalog, Reading, Stories}

  def index(conn, _params) do
    reader_id = conn.assigns.reader_id

    inklinks =
      for entry <- Catalog.list() do
        %{
          entry: entry,
          playable: playable(entry.id),
          current: Reading.current(reader_id, entry.id),
          finished: Reading.last_finished(reader_id, entry.id)
        }
      end

    render(conn, :index, page_title: "Library", inklinks: inklinks)
  end

  # `:ok`, or what the engine says it cannot do yet.
  defp playable(id) do
    case Stories.fetch(id) do
      {:ok, _} -> :ok
      {:error, {:unsupported, reasons}} -> {:unsupported, reasons}
      {:error, _} -> {:unsupported, ["an IR file the engine cannot read"]}
    end
  end
end
