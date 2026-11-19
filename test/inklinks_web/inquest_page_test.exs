defmodule InklinksWeb.InquestPageTest do
  @moduledoc """
  Flow D through the page, on the Littlejon fixture: what the Linker sees
  and, above all, what the page never holds before a group is opened.
  """
  use InklinksWeb.ConnCase, async: true

  import Dstar.Test

  @fixture "ex4-littlejon-thornbury"
  @forks ["Free her, unseen", "Speak in Sister Agathe’s ear"]

  setup %{conn: conn} do
    conn = post(conn, ~p"/inklinks/#{@fixture}/readings")
    %{conn: recycle(conn), path: redirected_to(conn)}
  end

  describe "a Linker reading an Inklink with Inquests" do
    test "sees the Inquest button and their count, and nothing of the forks", %{
      conn: conn,
      path: path
    } do
      html = conn |> get(path) |> html_response(200)

      assert html =~ "Inquest</button>"
      assert html =~ "3 Inquests left"
      refute_forks(html)
    end
  end

  describe "pressing Inquest" do
    test "opens the box first, as a modal dialog", %{conn: conn, path: path} do
      html = conn |> send_event(path, "inquest") |> patches()

      assert html =~ "<dialog"
      assert html =~ "el.showModal()"
      assert html =~ "What would you change here?"
      assert html =~ "Skip"
    end
  end

  describe "answering the box on a Nib with forks" do
    setup %{conn: conn, path: path} do
      send_event(conn, path, "inquest")
      %{answered: send_event(conn, path, "inquest-answer", %{"wanted" => "Save her."})}
    end

    test "enters Inquest mode, says so, and still holds no fork", %{answered: answered} do
      html = patches(answered)

      assert html =~ ~s(data-mode="inquest")
      assert html =~ "Inquest mode."
      assert html =~ ~s(id="announce")
      refute_forks(html)
    end

    test "a reload lands back in Inquest mode, and still holds no fork", %{conn: conn, path: path} do
      html = conn |> get(path) |> html_response(200)

      assert html =~ ~s(data-mode="inquest")
      refute_forks(html)
    end

    test "looking opens the Link into its forks, in order, in a View Transition, and announces them",
         %{conn: conn, path: path} do
      looked = send_event(conn, path, "look:here:obey_at_thornbury")
      html = patches(looked)

      assert looked |> sse_events() |> Enum.any?(&("useViewTransition true" in &1.data))
      assert html =~ "data-open"
      [first, second] = @forks
      assert {a, _} = :binary.match(html, first)
      assert {b, _} = :binary.match(html, second)
      assert a < b
      assert html =~ "take-fork%3Afree_the_widow"
      assert html =~ "2 other paths: #{first}; #{second}."
    end

    test "opening one group closes any other", %{conn: conn, path: path} do
      send_event(conn, path, "look:here:obey_at_thornbury")
      html = conn |> send_event(path, "tap:here:watch_what_unfolds") |> patches()

      # Make yourself watch hides nothing, so it asks; and the open group is gone
      assert html =~ "What did you want instead of “Make yourself watch”?"
    end

    test "after a look, a reload still holds no fork", %{conn: conn, path: path} do
      send_event(conn, path, "look:here:obey_at_thornbury")

      conn |> get(path) |> html_response(200) |> refute_forks()
    end

    test "taking a fork goes down it and spends one Inquest", %{conn: conn, path: path} do
      send_event(conn, path, "look:here:obey_at_thornbury")
      html = conn |> send_event(path, "take-fork:speak_in_her_ear") |> patches()

      assert html =~ ~s(data-nib="ch2_voice")
      assert html =~ "You took another path. 2 Inquests left."
    end

    test "a forged take of a fork never looked at changes nothing", %{conn: conn, path: path} do
      html = conn |> send_event(path, "take-fork:free_the_widow") |> patches()

      assert html =~ ~s(data-nib="ch2")
      refute_forks(html)
    end

    test "answering \"what did you want instead\" leaves Inquest mode and hands back the choice",
         %{conn: conn, path: path} do
      send_event(conn, path, "tap:here:watch_what_unfolds")
      html = conn |> send_event(path, "wanted-answer", %{"wanted" => "Look away."}) |> patches()

      assert html =~ ~s(data-nib="ch2")
      refute html =~ ~s(data-mode="inquest")
      assert html =~ "Noted. Choose a Link."
    end
  end

  describe "an Inquest at ch3, after obeying at ch2" do
    setup %{conn: conn, path: path} do
      send_event(conn, path, "take:obey_at_thornbury")
      send_event(conn, path, "inquest")
      %{answered: send_event(conn, path, "inquest-skip")}
    end

    test "shows the choice it could undo, without its forks", %{answered: answered} do
      html = patches(answered)

      assert html =~ "Back when you chose “Stay at Eyrad’s side”"
      assert html =~ "look%3A2%3Aobey_at_thornbury"
      refute_forks(html)
    end

    test "opens that earlier Link into only the forks asked for from here, and takes one",
         %{conn: conn, path: path} do
      html = conn |> send_event(path, "look:2:obey_at_thornbury") |> patches()

      assert html =~ "Back when you chose “Stay at Eyrad’s side”: Another path: Free her, unseen."
      refute html =~ "Speak in Sister Agathe’s ear"

      html = conn |> send_event(path, "take-fork:free_the_widow") |> patches()
      assert html =~ ~s(data-nib="ch2_alt")
    end
  end

  describe "an Inklink without Inquests" do
    test "shows no Inquest button, and ignores a forged Inquest", %{conn: conn} do
      ex3 = post(conn, ~p"/inklinks/ex3-the-fall-of-the-old-regime/readings")
      path = redirected_to(ex3)
      conn = recycle(ex3)

      refute conn |> get(path) |> html_response(200) =~ "Inquest</button>"
      refute conn |> send_event(path, "inquest") |> patches() =~ "<dialog"
    end
  end

  defp refute_forks(html) do
    for fork <- @forks, do: refute(html =~ fork)
    refute html =~ "free_the_widow"
    refute html =~ "speak_in_her_ear"
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
