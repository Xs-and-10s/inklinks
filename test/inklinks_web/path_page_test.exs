defmodule InklinksWeb.PathPageTest do
  @moduledoc """
  The path page on the Littlejon fixture: what a Linker sees of their own
  reading, and that it shows no fork they never looked at.
  """
  use InklinksWeb.ConnCase, async: true

  alias Inklinks.{Inquest, Reading}

  @fixture "ex4-littlejon-thornbury"

  setup %{conn: conn} do
    conn = post(conn, ~p"/inklinks/#{@fixture}/readings")
    "/readings/" <> id = redirected_to(conn)
    reader_id = get_session(conn, :reader_id)
    {:ok, reading} = Reading.load(id, reader_id)
    %{conn: recycle(conn), reading: reading}
  end

  describe "a Linker who went back from ch3 and freed the widow" do
    setup %{conn: conn, reading: reading} do
      {:ok, reading} = Reading.take(reading, "watch_what_unfolds")
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)
      [_, %{at: at} | _] = Reading.places(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury", at)
      {:ok, reading} = Inquest.take(reading, "free_the_widow")
      %{html: conn |> get(~p"/readings/#{reading.id}/path") |> html_response(200)}
    end

    test "sees each Nib in order, how they got there, and the path they left", %{html: html} do
      assert html =~ "Your path"
      assert html =~ "You began here."
      assert html =~ "You chose “Make yourself watch”."

      assert html =~
               "You went back, and took “Free her, unseen”, instead of “Stay at Eyrad’s side”."

      assert html =~ "A path you left"
      assert html =~ "From here, you went back with an Inquest."
      assert html =~ ~s(style="--lanes: 2")
    end

    test "is told everything in text; the graph is hidden from assistive tech", %{html: html} do
      assert html =~ ~s(<span data-graph aria-hidden="true">)
      assert html =~ ~s(<ol aria-label="Every Nib you were shown, in order")
    end

    test "never sees the fork they did not look at", %{html: html} do
      refute html =~ "Speak in"
    end
  end

  describe "someone else" do
    test "gets a 404 for a reading that is not theirs", %{reading: reading} do
      stranger = build_conn() |> get(~p"/readings/#{reading.id}/path")
      assert response(stranger, 404)
    end
  end

  describe "the reader" do
    test "has a way to the path from the end of a reading", %{conn: conn, reading: reading} do
      {:ok, reading} = Reading.take(reading, "watch_what_unfolds")
      {:ok, reading} = Reading.take(reading, "keep_the_book")
      assert Reading.view(reading).done
      html = conn |> get(~p"/readings/#{reading.id}") |> html_response(200)
      assert html =~ ~s(href="/readings/#{reading.id}/path")

      library = conn |> get(~p"/") |> html_response(200)
      assert library =~ "Your last path"
    end
  end
end
