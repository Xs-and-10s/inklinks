defmodule Inklinks.Engine.Stub.Emphasis do
  @moduledoc """
  Lowers Inkjot emphasis in a paragraph into styled runs.

  IR 2 passes `*italic*`, `**bold**` and `***bold italic***` through as
  literal asterisks. IR 3 should lower them at compile time
  (docs/ir3-requests.md); until then the stub does it here, so the renderer
  only ever sees runs:

      iex> Inklinks.Engine.Stub.Emphasis.lower(["I’ll get *me* noticed."])
      ["I’ll get ", %{style: [:italic], parts: ["me"]}, " noticed."]

  The rules are Inkjot v0.6's:

    * `*` italic, `**` bold, `***` both; they nest (`**a *b* c**`);
    * underscores are literal;
    * an unmatched `*` is literal, and so is a run of four or more;
    * `\\*` is an asterisk;
    * an opening run must be followed by something other than a space, and
      a closing run preceded by one, so `2 * 3` stays arithmetic;
    * emphasis never crosses a paragraph: this works on one at a time;
    * an insert (`{"value": …}`) counts as text, so `*{leo.aka}*` works.
  """

  @type style :: :italic | :bold
  @type part :: String.t() | %{style: [style()], parts: [part()]} | map()

  @doc "Lowers one paragraph: a list of strings and inserts."
  @spec lower([part()]) :: [part()]
  def lower(paragraph) when is_list(paragraph) do
    paragraph
    |> tokenize()
    |> classify()
    |> parse()
  end

  # -- tokens ------------------------------------------------------------------
  # {:text, string} | {:insert, map} | {:run, n, prev, next}
  # prev/next: :space, :content or :edge (a paragraph's start or end).

  defp tokenize(paragraph) do
    Enum.flat_map(paragraph, fn
      text when is_binary(text) -> scan(text, "", [])
      insert -> [{:insert, insert}]
    end)
  end

  defp scan("", acc, tokens), do: Enum.reverse(push_text(acc, tokens))

  defp scan("\\*" <> rest, acc, tokens), do: scan(rest, acc <> "*", tokens)

  defp scan("*" <> _ = text, acc, tokens) do
    run = text |> String.graphemes() |> Enum.take_while(&(&1 == "*")) |> length()
    rest = binary_part(text, run, byte_size(text) - run)
    scan(rest, "", [{:run, run, last_char(acc)} | push_text(acc, tokens)])
  end

  defp scan(text, acc, tokens) do
    {char, rest} = String.next_grapheme(text)
    scan(rest, acc <> char, tokens)
  end

  defp push_text("", tokens), do: tokens
  defp push_text(acc, tokens), do: [{:text, acc} | tokens]

  defp last_char(""), do: nil
  defp last_char(acc), do: String.last(acc)

  # Work out what sits on each side of every run of asterisks.
  defp classify(tokens) do
    tokens
    |> Enum.with_index()
    |> Enum.map(fn
      {{:run, n, _}, i} -> {:run, n, side(tokens, i - 1, :before), side(tokens, i + 1, :after)}
      {token, _} -> token
    end)
  end

  defp side(_tokens, i, _) when i < 0, do: :edge

  defp side(tokens, i, which) do
    case Enum.at(tokens, i) do
      nil ->
        :edge

      {:insert, _} ->
        :content

      {:run, _, _} ->
        :content

      {:text, text} ->
        char_kind(if which == :before, do: String.last(text), else: String.first(text))
    end
  end

  defp char_kind(char), do: if(String.trim(char) == "", do: :space, else: :content)

  # -- parsing -------------------------------------------------------------------
  # A stack of open frames; the bottom frame (n: nil) is the paragraph.

  defp parse(tokens) do
    tokens
    |> Enum.reduce([%{n: nil, parts: []}], &step/2)
    |> close_all()
  end

  defp step({:text, text}, stack), do: add(stack, text)
  defp step({:insert, insert}, stack), do: add(stack, insert)

  defp step({:run, n, before, after_}, stack) when n <= 3 do
    can_open = after_ == :content
    can_close = before == :content

    cond do
      can_close and open?(stack, n) -> close(stack, n)
      can_open -> [%{n: n, parts: []} | stack]
      true -> add(stack, stars(n))
    end
  end

  defp step({:run, n, _, _}, stack), do: add(stack, stars(n))

  defp open?(stack, n), do: Enum.any?(stack, &(&1.n == n))

  # Close the nearest frame opened with `n` asterisks. Frames opened above it
  # and never closed become literal text inside it.
  defp close([%{n: n} = frame, parent | rest], n) do
    node = %{style: style(n), parts: merge(Enum.reverse(frame.parts))}
    [%{parent | parts: [node | parent.parts]} | rest]
  end

  defp close([frame, below | rest], n) do
    close([%{below | parts: literal(frame) ++ below.parts} | rest], n)
  end

  defp close_all([root]), do: merge(Enum.reverse(root.parts))

  defp close_all([frame, below | rest]) do
    close_all([%{below | parts: literal(frame) ++ below.parts} | rest])
  end

  # A frame that never closed: its asterisks, then what it held, as parts in
  # reverse order (the order frames keep them in).
  defp literal(frame), do: frame.parts ++ [stars(frame.n)]

  defp add([frame | rest], part), do: [%{frame | parts: [part | frame.parts]} | rest]

  defp style(1), do: [:italic]
  defp style(2), do: [:bold]
  defp style(3), do: [:italic, :bold]

  defp stars(n), do: String.duplicate("*", n)

  # Join neighbouring strings: ["a", "*", "b"] → ["a*b"].
  defp merge(parts) do
    parts
    |> Enum.reduce([], fn
      text, [prev | acc] when is_binary(text) and is_binary(prev) -> [prev <> text | acc]
      part, acc -> [part | acc]
    end)
    |> Enum.reverse()
  end
end
