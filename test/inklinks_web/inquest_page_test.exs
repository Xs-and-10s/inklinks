defmodule InklinksWeb.InquestPageTest do
  @moduledoc """
  Flow D through the page, on the Littlejon fixture: what the Linker sees
  and, above all, what the page never holds before a flip.
  """
  use InklinksWeb.ConnCase, async: true

  import Dstar.Test

  @fixture "ex4-littlejon-thornbury"
  @fork "Free her, unseen"

  setup %{conn: conn} do
    conn = post(conn, ~p"/inklinks/#{@fixture}/readings")
    %{conn: recycle(conn), path: redirected_to(conn)}
  end

  describe "a Linker reading an Inklink with Inquests" do
    test "sees the Inquest button and their count, and nothing of the fork", %{
      conn: conn,
      path: path
    } do
      html = conn |> get(path) |> html_response(200)

      assert html =~ "Inquest</button>"
      assert html =~ "3 Inquests left"
      refute html =~ @fork
      refute html =~ "free_the_widow"
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

  describe "answering the box on a Nib with a fork" do
    setup %{conn: conn, path: path} do
      send_event(conn, path, "inquest")
      %{answered: send_event(conn, path, "inquest-answer", %{"wanted" => "Save her."})}
    end

    test "enters Inquest mode, says so, and still holds no fork", %{answered: answered} do
      html = patches(answered)

      assert html =~ ~s(data-mode="inquest")
      assert html =~ "Inquest mode."
      assert html =~ ~s(id="announce")
      refute html =~ @fork
    end

    test "a reload lands back in Inquest mode, and still holds no fork", %{conn: conn, path: path} do
      html = conn |> get(path) |> html_response(200)

      assert html =~ ~s(data-mode="inquest")
      refute html =~ @fork
    end

    test "looking at the canon Link flips it, in a View Transition, and announces it",
         %{conn: conn, path: path} do
      looked = send_event(conn, path, "look:obey_at_thornbury")
      [flip | _] = sse_events(looked)
      html = patches(looked)

      assert "useViewTransition true" in flip.data
      assert html =~ "data-flipped"
      assert html =~ @fork
      assert html =~ "take-fork%3Afree_the_widow"
      assert html =~ "Another path: #{@fork}."
    end

    test "after a look, a reload still holds no fork", %{conn: conn, path: path} do
      send_event(conn, path, "look:obey_at_thornbury")

      refute conn |> get(path) |> html_response(200) =~ @fork
    end

    test "taking the fork goes down it and spends one Inquest", %{conn: conn, path: path} do
      send_event(conn, path, "look:obey_at_thornbury")
      html = conn |> send_event(path, "take-fork:free_the_widow") |> patches()

      assert html =~ ~s(data-nib="ch2_alt")
      assert html =~ "You took another path. 2 Inquests left."
    end

    test "a forged take of a fork never looked at changes nothing", %{conn: conn, path: path} do
      html = conn |> send_event(path, "take-fork:free_the_widow") |> patches()

      assert html =~ ~s(data-nib="ch2")
      refute html =~ @fork
    end

    test "tapping a canon Link with no fork asks what they wanted instead", %{
      conn: conn,
      path: path
    } do
      html = conn |> send_event(path, "tap:shut_your_eyes") |> patches()

      assert html =~ "What did you want instead of “Shut your eyes”?"
    end

    test "answering that leaves Inquest mode and hands the choice back", %{conn: conn, path: path} do
      send_event(conn, path, "tap:shut_your_eyes")
      html = conn |> send_event(path, "wanted-answer", %{"wanted" => "Watch."}) |> patches()

      assert html =~ ~s(data-nib="ch2")
      refute html =~ ~s(data-mode="inquest")
      assert html =~ "Noted. Choose a Link."
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
