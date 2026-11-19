defmodule InklinksWeb.ReadingPageTest do
  use InklinksWeb.ConnCase, async: true

  import Dstar.Test

  @ex3 "ex3-the-fall-of-the-old-regime"

  describe "the library" do
    test "offers Ex 3 to read, and says why Ex 1 cannot be read yet", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(action="/inklinks/#{@ex3}/readings")
      assert html =~ "Not playable yet"
      assert html =~ "cohort mode"
    end
  end

  describe "a reader who presses Read" do
    test "starts a reading and lands on its first Nib", %{conn: conn} do
      conn = post(conn, ~p"/inklinks/#{@ex3}/readings")
      assert "/readings/" <> _ = path = redirected_to(conn)

      html = conn |> recycle() |> get(path) |> html_response(200)

      assert html =~ "The front room is full of shoes."
      assert html =~ ~s(data-who="leo")
      assert html =~ "/_event/take%3Aarrival%231"
    end

    test "comes back to an unfinished reading, unless they ask to begin again", %{conn: conn} do
      first = post(conn, ~p"/inklinks/#{@ex3}/readings")
      again = first |> recycle() |> post(~p"/inklinks/#{@ex3}/readings")
      fresh = first |> recycle() |> post(~p"/inklinks/#{@ex3}/readings", %{"again" => "true"})

      assert redirected_to(again) == redirected_to(first)
      refute redirected_to(fresh) == redirected_to(first)
    end
  end

  describe "taking a Link" do
    setup %{conn: conn} do
      conn = post(conn, ~p"/inklinks/#{@ex3}/readings")
      %{conn: recycle(conn), path: redirected_to(conn)}
    end

    test "answers with the next Nib, patched in a View Transition", %{conn: conn, path: path} do
      conn = take(conn, path, "arrival#1")

      data = nib_patch(conn)
      assert "useViewTransition true" in data
      html = Enum.join(data, "\n")
      assert html =~ "It goes on twice."
      assert html =~ ~s(id="nib")
    end

    test "that is not on offer shows the Nib as it is, and records nothing", %{
      conn: conn,
      path: path
    } do
      conn = take(conn, path, "state#1")

      html = conn |> nib_patch() |> Enum.join("\n")
      assert html =~ "The front room is full of shoes."
    end

    test "in someone else's reading is not found", %{path: path} do
      stranger = build_conn()
      assert stranger |> get(path) |> response(404)
      assert stranger |> take(path, "arrival#1") |> response(404)
    end
  end

  defp nib_patch(conn) do
    conn
    |> sse_events()
    |> Enum.find(fn %{data: data} -> Enum.any?(data, &(&1 =~ ~s(id="nib"))) end)
    |> Map.fetch!(:data)
  end

  defp take(conn, path, link) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("datastar-request", "true")
    |> post(
      path <> "/_event/" <> URI.encode("take:" <> link, &URI.char_unreserved?/1),
      ~s({"csrf":"t"})
    )
  end
end
