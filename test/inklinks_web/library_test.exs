defmodule InklinksWeb.LibraryTest do
  use InklinksWeb.ConnCase, async: true

  describe "a reader opening the library" do
    test "sees every shipped Inklink by title", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "<h1>Library</h1>"
      assert html =~ "The Fall of the Old Regime"
      assert html =~ "The Night Train"
      assert html =~ "The Ninefold Cell"
    end

    test "loads Datastar with Rocket, from this site, with the CSRF token as a signal",
         %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(src="/vendor/datastar-rocket-1.0.5.js")
      assert html =~ "data-signals:csrf="
    end
  end
end
