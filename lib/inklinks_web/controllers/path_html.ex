defmodule InklinksWeb.PathHTML do
  @moduledoc """
  The path page. Each row is an `li`: its text says everything (how the
  Linker got there, how the Nib began, what they left), and the graph
  beside it is drawing only, hidden from assistive tech.

  The graph is CSS, not SVG: each row draws its own slice of every line
  that crosses it (`data-seg`: `through`, `top`, `bottom`, or an `elbow`
  out of a dot into another lane), so rows can grow with their text, as
  they do on a narrow screen, and the lines still meet.
  """
  use InklinksWeb, :html

  alias Inklinks.Reading

  embed_templates "path_html/*"

  @doc "How the Linker came to a row."
  def arrival(%{via: nil}), do: "You began here."

  def arrival(%{via: %{kind: :link, label: label}}), do: "You chose #{Reading.quoted(label)}."

  def arrival(%{via: %{kind: :fork, label: label, instead: instead, back: back}}) do
    instead = if instead, do: ", instead of #{Reading.quoted(instead)}", else: ""
    went = if back, do: "You went back, and took ", else: "An Inquest: you took "
    "#{went}#{Reading.quoted(label)}#{instead}."
  end

  @doc "The summary line under the title."
  def summary(timeline) do
    nibs = length(timeline.rows)
    left = Enum.count(timeline.rows, &(not &1.live))
    back = Enum.count(timeline.rows, & &1.went_back)

    [
      plural(nibs - left, "Nib", "Nibs") <> " on this path",
      timeline.inquests > 0 && plural(timeline.inquests, "fork taken", "forks taken"),
      back > 0 && plural(back, "time you went back", "times you went back")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp plural(1, one, _), do: "1 #{one}"
  defp plural(n, _, many), do: "#{n} #{many}"
end
