defmodule InklinksWeb.ReadingController do
  @moduledoc """
  Starting a reading: a plain form POST from the library (or from an
  ending's "Read again"), then a redirect to the reader.

  Without `again`, a reader who has an unfinished reading of the Inklink
  goes back to it rather than starting over.
  """
  use InklinksWeb, :controller

  alias Inklinks.Reading

  def create(conn, %{"inklink_id" => inklink_id} = params) do
    reader_id = conn.assigns.reader_id
    current = params["again"] != "true" && Reading.current(reader_id, inklink_id)

    if current do
      redirect(conn, to: ~p"/readings/#{current}")
    else
      case Reading.start(reader_id, inklink_id) do
        {:ok, reading} ->
          redirect(conn, to: ~p"/readings/#{reading.id}")

        {:error, _} ->
          conn |> put_status(404) |> text("This Inklink cannot be read yet.")
      end
    end
  end
end
