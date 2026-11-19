defmodule Inklinks.Events.CatalogTest do
  use ExUnit.Case, async: true

  alias Inklinks.Events.Catalog

  describe "the catalogue" do
    test "is the table in docs/events.md, word for word" do
      assert File.read!("docs/events.md") =~ Catalog.markdown()
    end

    test "lists every event type the platform writes, and nothing it doesn't" do
      written =
        Path.wildcard("lib/**/*.ex")
        |> Enum.reject(&String.ends_with?(&1, "events/catalog.ex"))
        |> Enum.flat_map(
          &Regex.scan(~r/type: "([a-z_]+)"/, File.read!(&1), capture: :all_but_first)
        )
        |> List.flatten()
        |> MapSet.new()
        |> MapSet.delete("reading")

      assert written == MapSet.new(Catalog.all(), & &1.type)
    end

    test "gives every type one actor and no key twice" do
      for e <- Catalog.all() do
        assert e.actor in [:linker, :engine, :platform]
        keys = e.required ++ e.optional
        assert keys == Enum.uniq(keys), e.type
      end
    end
  end

  describe "stamp!/1" do
    test "stamps the actor of a well-formed event" do
      event = %{type: "link_taken", data: %{"link" => "a", "nib" => "n", "label" => "A"}}
      assert Catalog.stamp!(event).actor == "linker"
    end

    test "allows optional keys and refuses unknown types, missing keys and extra keys" do
      look = %{"nib" => "n", "link" => "l", "fork" => "f", "label" => "F"}
      assert Catalog.stamp!(%{type: "fork_looked", data: Map.put(look, "at", "ch2")})

      assert_raise ArgumentError, ~r/unknown/, fn ->
        Catalog.stamp!(%{type: "nib_eaten", data: %{}})
      end

      assert_raise ArgumentError, ~r/missing/, fn ->
        Catalog.stamp!(%{type: "fork_looked", data: Map.delete(look, "fork")})
      end

      assert_raise ArgumentError, ~r/unexpected/, fn ->
        Catalog.stamp!(%{type: "fork_looked", data: Map.put(look, "x", 1)})
      end
    end
  end
end
