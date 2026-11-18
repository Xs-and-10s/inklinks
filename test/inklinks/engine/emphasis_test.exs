defmodule Inklinks.Engine.EmphasisTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Inklinks.Engine.Stub.Emphasis

  doctest Emphasis

  describe "Inkjot emphasis" do
    test "one, two and three asterisks are italic, bold, and both" do
      assert Emphasis.lower(["*a* **b** ***c***"]) == [
               %{style: [:italic], parts: ["a"]},
               " ",
               %{style: [:bold], parts: ["b"]},
               " ",
               %{style: [:italic, :bold], parts: ["c"]}
             ]
    end

    test "nests" do
      assert Emphasis.lower(["**he *never* said**"]) == [
               %{style: [:bold], parts: ["he ", %{style: [:italic], parts: ["never"]}, " said"]}
             ]
    end

    test "leaves underscores alone" do
      assert Emphasis.lower(["my_list and _this_"]) == ["my_list and _this_"]
    end

    test "leaves an unmatched asterisk, and a run of four, as they are" do
      assert Emphasis.lower(["a *lone star"]) == ["a *lone star"]
      assert Emphasis.lower(["****"]) == ["****"]
    end

    test "reads \\* as an asterisk" do
      assert Emphasis.lower(["\\*not italic\\*"]) == ["*not italic*"]
    end

    test "leaves arithmetic alone: an asterisk between spaces opens nothing" do
      assert Emphasis.lower(["2 * 3 * 4"]) == ["2 * 3 * 4"]
    end

    test "wraps an insert" do
      value = %{"value" => %{"get" => ["leo", "aka"]}}
      assert Emphasis.lower(["*", value, "*"]) == [%{style: [:italic], parts: [value]}]
    end

    test "never crosses a paragraph" do
      assert Emphasis.lower(["*begins here"]) == ["*begins here"]
      assert Emphasis.lower(["ends here*"]) == ["ends here*"]
    end
  end

  describe "any text written with asterisks" do
    property "lowers to exactly the styled runs it was written from" do
      check all(tree <- styled_text()) do
        assert runs(Emphasis.lower([source(tree)])) == runs(tree)
      end
    end

    property "is unchanged when it has no asterisks or backslashes" do
      check all(text <- string(:printable)) do
        plain = String.replace(text, ["*", "\\"], "")
        assert Emphasis.lower([plain]) == if(plain == "", do: [], else: [plain])
      end
    end
  end

  # -- generators --------------------------------------------------------------
  # A paragraph is a list of words and styled spans, separated by spaces. A
  # span starts and ends with a word (so `**` never touches `*`), and never
  # repeats a style it is already inside.

  defp styled_text, do: sequence([])

  defp sequence(inherited) do
    gen all(items <- list_of(item(inherited), min_length: 1, max_length: 4)) do
      Enum.intersperse(items, " ")
    end
  end

  defp item(inherited) do
    styles =
      Enum.reject(
        [[:italic], [:bold], [:italic, :bold]],
        &Enum.any?(&1, fn s -> s in inherited end)
      )

    if styles == [] or length(inherited) > 1 do
      word()
    else
      frequency([
        {3, word()},
        {1,
         gen all(
               style <- member_of(styles),
               first <- word(),
               middle <- list_of(item(inherited ++ style), max_length: 2),
               last <- word()
             ) do
           %{style: style, parts: Enum.intersperse([first | middle] ++ [last], " ")}
         end}
      ])
    end
  end

  defp word, do: string([?a..?z, ?A..?Z, ?0..?9, ?_, ?’], min_length: 1, max_length: 6)

  # Inkjot source for a tree.
  defp source(parts) when is_list(parts), do: Enum.map_join(parts, &source/1)
  defp source(text) when is_binary(text), do: text

  defp source(%{style: style, parts: parts}) do
    stars = stars(style)
    stars <> source(parts) <> stars
  end

  defp stars([:italic]), do: "*"
  defp stars([:bold]), do: "**"
  defp stars([:italic, :bold]), do: "***"

  # A tree flattened to runs of {text, styles}, neighbours with the same
  # styles merged: two trees that render alike have the same runs.
  defp runs(parts), do: parts |> flatten(MapSet.new()) |> merge()

  defp flatten(parts, styles) when is_list(parts), do: Enum.flat_map(parts, &flatten(&1, styles))
  defp flatten(text, styles) when is_binary(text), do: [{text, styles}]

  defp flatten(%{style: style, parts: parts}, styles),
    do: flatten(parts, MapSet.union(styles, MapSet.new(style)))

  defp merge(runs) do
    runs
    |> Enum.reject(fn {text, _} -> text == "" end)
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn chunk -> {Enum.map_join(chunk, &elem(&1, 0)), chunk |> hd() |> elem(1)} end)
  end
end
