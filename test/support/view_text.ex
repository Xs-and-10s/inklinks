defmodule Inklinks.ViewText do
  @moduledoc """
  A view as plain text, the way `inkjot play` prints it: speech as
  `Leo (gently): …`, list entries one per line with `(mark)`, struck ones
  as `~~…~~`, emphasis as `*…*`. So the compiler's own Ex 3 tests can be
  checked here word for word.
  """

  def text(%{ink: sections}) do
    sections
    |> Enum.flat_map(& &1.blocks)
    |> Enum.flat_map(&lines/1)
    |> Enum.join("\n")
  end

  def label(%{label: parts}), do: plain(parts)

  defp lines(%{type: :prose, paragraphs: ps}), do: Enum.map(ps, &plain/1)
  defp lines(%{type: :beat}), do: []

  defp lines(%{type: :speech, name: name, direction: dir, paragraphs: [first | rest]}) do
    lead = if dir, do: "#{name} (#{dir}): ", else: "#{name}: "
    [lead <> plain(first) | Enum.map(rest, &plain/1)]
  end

  defp lines(%{type: :list, items: items}) do
    for item <- items do
      text = if item.mark, do: "#{item.text} (#{item.mark})", else: item.text
      if item.struck, do: "~~#{text}~~", else: text
    end
  end

  def plain(parts) do
    Enum.map_join(parts, fn
      text when is_binary(text) -> text
      %{style: style, parts: inner} -> stars(style) <> plain(inner) <> stars(style)
    end)
  end

  defp stars([:italic]), do: "*"
  defp stars([:bold]), do: "**"
  defp stars(_), do: "***"
end
