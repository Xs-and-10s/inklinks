defmodule Inklinks.CatalogTest do
  use ExUnit.Case, async: true

  alias Inklinks.Catalog

  @moduletag :tmp_dir

  describe "a folder of IR files" do
    test "is listed by title, with each Inklink's kind, mode and Inquests", %{tmp_dir: dir} do
      # Given two Inklinks, one whose Inker declared three Inquests
      write!(dir, "zeta.json", ir("A Story", [kind("story"), mode("solo"), inquests(3)]))
      write!(dir, "alpha.json", ir("The Game", [kind("game"), mode("cohort")]))

      # When the catalog lists the folder
      [story, game] = Catalog.list(dir)

      # Then they come in title order, ids from their file names
      assert %{id: "zeta", title: "A Story", kind: "story", mode: "solo", inquests: 3} = story
      assert %{id: "alpha", title: "The Game", kind: "game", mode: "cohort", inquests: 0} = game
    end

    test "skips files that are not Inklinks", %{tmp_dir: dir} do
      write!(dir, "notes.json", ~s({"hello": "world"}))
      write!(dir, "broken.json", "{")
      write!(dir, "real.json", ir("Real", []))

      assert [%{id: "real"}] = Catalog.list(dir)
    end

    test "finds an Inklink only by an id it listed", %{tmp_dir: dir} do
      write!(dir, "real.json", ir("Real", []))

      assert {:ok, %{title: "Real"}} = Catalog.fetch("real", dir)
      assert :error = Catalog.fetch("../real", dir)
      assert :error = Catalog.fetch("missing", dir)
    end
  end

  describe "the shipped Inklinks" do
    test "include Ex 3, a solo story" do
      assert {:ok, ex3} = Catalog.fetch("ex3-the-fall-of-the-old-regime")
      assert %{title: "The Fall of the Old Regime", kind: "story", mode: "solo", ir: "2"} = ex3
    end
  end

  defp ir(title, config), do: JSON.encode!(%{"ir" => "2", "title" => title, "config" => config})
  defp kind(k), do: %{"setting" => "kind", "value" => k}
  defp mode(m), do: %{"setting" => "mode", "value" => m}
  defp inquests(n), do: %{"declare" => "resource", "id" => "inquests", "value" => n}
  defp write!(dir, name, body), do: File.write!(Path.join(dir, name), body)
end
