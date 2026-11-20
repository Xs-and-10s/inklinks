defmodule InklinksWeb.PathController do
  @moduledoc """
  A reading's path, for its reader: `Inklinks.Timeline`, drawn top to
  bottom so it scrolls on a phone. A plain page; nothing on it changes
  until the reading moves on. Anyone else's reading is a 404, as on the
  reader.
  """
  use InklinksWeb, :controller

  alias Inklinks.{Reading, Timeline}

  def show(conn, %{"id" => id}) do
    case Reading.load(id, conn.assigns.reader_id) do
      {:ok, reading} ->
        timeline = Timeline.build(reading)

        render(conn, :show,
          page_title: "Your path: #{timeline.title}",
          reading: reading,
          timeline: timeline
        )

      {:error, _} ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
