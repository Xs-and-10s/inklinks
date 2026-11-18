defmodule InklinksWeb.Ink do
  @moduledoc """
  Renders an engine's view as HTML: the Ink of a Nib and its Links.

  The markup carries meaning, and the stylesheet styles that meaning:

    * a passage is a `section` with `data-passage`;
    * a line of speech is a `p` with `data-who`; the speaker is `b` (offset
      text) and the stage direction `i` (another voice);
    * a beat is an `hr` with `data-beat`, the pause it stands for, so timed
      reveals can come later as CSS without changing the server;
    * emphasis is `i` and `b`: Inkjot's asterisks name typography, and in
      fiction italics are mostly thoughts and titles, not stress;
    * a struck list entry is `s`: no longer accurate, still visible.
  """
  use Phoenix.Component

  attr :sections, :list, required: true

  def ink(assigns) do
    ~H"""
    <section :for={section <- @sections} data-passage={section.passage}>
      <.block :for={block <- section.blocks} block={block} />
    </section>
    """
  end

  attr :block, :map, required: true

  def block(%{block: %{type: :prose}} = assigns) do
    ~H"""
    <p :for={paragraph <- @block.paragraphs}><.parts parts={paragraph} /></p>
    """
  end

  def block(%{block: %{type: :speech}} = assigns) do
    ~H"""
    <p :for={{paragraph, i} <- Enum.with_index(@block.paragraphs)} data-who={@block.who}>
      <b :if={i == 0}>{@block.name}</b>{if i == 0 && @block.direction, do: " "}<i :if={
        i == 0 && @block.direction
      }>({@block.direction})</i>
      <.parts parts={paragraph} />
    </p>
    """
  end

  def block(%{block: %{type: :beat}} = assigns) do
    ~H"""
    <hr data-beat={@block.time || "1"} />
    """
  end

  def block(%{block: %{type: :list}} = assigns) do
    ~H"""
    <ul data-list>
      <li :for={item <- @block.items}>
        <%= if item.struck do %>
          <s>{item.text}</s>
        <% else %>
          {item.text}
        <% end %>
        <small :if={item.mark}>({item.mark})</small>
      </li>
    </ul>
    """
  end

  attr :parts, :list, required: true

  @doc "A paragraph or a label: text and styled runs, nested."
  def parts(assigns) do
    ~H"""
    <.run :for={part <- @parts} part={part} />
    """
  end

  attr :part, :any, required: true

  defp run(%{part: text} = assigns) when is_binary(text), do: ~H"{@part}"

  defp run(%{part: %{style: style}} = assigns) do
    assigns = assign(assigns, italic: :italic in style, bold: :bold in style)

    ~H"""
    <%= cond do %>
      <% @italic and @bold -> %>
        <b><i><.parts parts={@part.parts} /></i></b>
      <% @bold -> %>
        <b><.parts parts={@part.parts} /></b>
      <% true -> %>
        <i><.parts parts={@part.parts} /></i>
    <% end %>
    """
  end
end
