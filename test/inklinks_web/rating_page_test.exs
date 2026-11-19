defmodule InklinksWeb.RatingPageTest do
  use InklinksWeb.ConnCase, async: true

  import Dstar.Test

  @ex3 "ex3-the-fall-of-the-old-regime"
  @path ~w(arrival#1 trial#3 interval#1 testament#1 handoff#1 march#1 coup#1 state#1)

  setup %{conn: conn} do
    conn = post(conn, ~p"/inklinks/#{@ex3}/readings")
    %{conn: recycle(conn), path: redirected_to(conn)}
  end

  describe "reaching the finale" do
    test "brings the ratings box, closed until the end of the finale scrolls into view",
         %{conn: conn, path: path} do
      html =
        Enum.reduce(@path, nil, fn link, _ ->
          conn |> send_event(path, "take:" <> link) |> patches()
        end)

      assert html =~ "How was it?"
      assert html =~ "The ending"
      assert html =~ "The Inklink overall"
      refute html =~ "Your path"
      refute html =~ "el.showModal()"
      assert html =~ "data-rating-due"
      assert html =~ "data-on-intersect__once"
      assert html =~ "More…"
      assert html =~ "Rate this ending"
    end

    test "lists moments with the choice on its own line, never in doubled quotes", %{
      conn: conn,
      path: path
    } do
      for link <- @path, do: send_event(conn, path, "take:" <> link)
      html = conn |> get(path) |> html_response(200)

      assert html =~ "I wouldn’t change a thing"

      assert html =~
               ~r/<span>Where you chose<\/span>\s*<span data-chosen>\s*“They named me Skittles.”\s*<\/span>/

      assert html =~ ~r/<span data-chosen>\s*Run\s*<\/span>/
      refute html =~ "““"
      assert html =~ "Add another"
    end

    test "Add another saves the moment and strikes it, without closing the box", %{
      conn: conn,
      path: path
    } do
      for link <- @path, do: send_event(conn, path, "take:" <> link)

      html =
        conn
        |> send_event(path, "wish", %{"changeAt" => "4", "changeText" => "Take the treat."})
        |> patches()

      assert html =~ ~s(id="moments")
      assert html =~ "<s>Run</s>"
      assert html =~ "Saved. Pick another, or press Done."
      refute html =~ "Thank you"
    end

    test "a reload brings it back until it is answered", %{conn: conn, path: path} do
      for link <- @path, do: send_event(conn, path, "take:" <> link)

      assert conn |> get(path) |> html_response(200) =~ "How was it?"

      html =
        conn
        |> send_event(path, "rate", %{"ratingEnding" => "5", "ratingInklink" => "4"})
        |> patches()

      assert html =~ "Thank you. The Inker will read this."
      refute html =~ "data-rating-due"

      refute conn |> get(path) |> html_response(200) =~ "How was it?"
    end

    test "Not now puts it away for this reading", %{conn: conn, path: path} do
      for link <- @path, do: send_event(conn, path, "take:" <> link)
      send_event(conn, path, "rating-dismiss")

      refute conn |> get(path) |> html_response(200) =~ "How was it?"
    end
  end

  defp send_event(conn, path, event, signals \\ %{}) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("datastar-request", "true")
    |> post(
      path <> "/_event/" <> URI.encode(event, &URI.char_unreserved?/1),
      JSON.encode!(Map.put(signals, "csrf", "t"))
    )
  end

  defp patches(conn), do: conn |> sse_events() |> Enum.flat_map(& &1.data) |> Enum.join("\n")
end
