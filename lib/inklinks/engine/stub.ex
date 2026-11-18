defmodule Inklinks.Engine.Stub do
  @moduledoc """
  A small Elixir engine for stories, standing in for the Rust interpreter
  until the bridge exists. It follows the interpreter's rules (docs/run.md
  in inkjot-compiler-rust) for what it covers, and refuses the rest by name.

  Arriving at a passage runs its header (effects, `next:`), renders its
  body, and offers its Links. A `next:` carries straight on, so one step can
  pass through several passages (Ex 3's `arrival:name` leads into `trial`).
  The view keeps each passage's Ink as its own section.

  Rendering happens on arrival, not on `view/2`, because reading `aka`
  rolls dice: rendering twice would roll twice. The world keeps the view it
  rendered.
  """
  @behaviour Inklinks.Engine

  alias Inklinks.Engine.Stub.{Emphasis, Story, World}

  @max_next 64

  @impl true
  def load(json), do: Story.load(json)

  @impl true
  def meta(%Story{} = story) do
    %{title: story.title, kind: story.kind, mode: story.mode, inquests: story.inquests}
  end

  @impl true
  def start(%Story{} = story, seed) when is_integer(seed) do
    {:ok, story |> World.new(seed) |> arrive(story, story.start, [], 0)}
  end

  @impl true
  def view(_story, %World{view: view}), do: view

  @impl true
  def take(%Story{} = story, %World{} = w, link_id) do
    case Enum.find(w.offered, &(&1["id"] == link_id)) do
      nil ->
        {:error, :not_offered}

      link ->
        w = Enum.reduce(link["effects"] || [], w, &apply_effect(&1, [], story, &2))
        {:ok, arrive(w, story, link["target"], [], 0)}
    end
  end

  # Inquests come in milestone 3.
  @impl true
  def forks?(_story, _w), do: false

  @impl true
  def fork(_story, _w, _canon), do: :none

  @impl true
  def take_fork(_story, _w, _fork), do: {:error, :not_offered}

  # -- arriving ------------------------------------------------------------------

  defp arrive(_w, _story, name, _sections, depth) when depth > @max_next do
    raise "`next:` passes through more than #{@max_next} passages from `#{name}`: a loop?"
  end

  defp arrive(w, story, name, sections, depth) do
    passage = Map.fetch!(story.passages, name)
    w = update_in(w.visits, &Map.update(&1, name, 1, fn n -> n + 1 end))

    {w, next} =
      Enum.reduce(passage["header"], {w, nil}, fn
        %{"setting" => "next", "value" => target}, {w, _} ->
          {w, target}

        %{"effect" => effect} = s, {w, next} ->
          {apply_effect(effect, s["clauses"] || [], story, w), next}

        _, acc ->
          acc
      end)

    {blocks, links, w} = render(passage, story, w)
    sections = sections ++ [%{passage: name, blocks: blocks}]

    if next do
      arrive(w, story, next, sections, depth + 1)
    else
      %{w | at: name, offered: links, view: view_of(passage, sections, links, story)}
    end
  end

  defp view_of(passage, sections, links, story) do
    %{
      nib: passage["name"],
      ink: sections,
      links: Enum.map(links, &%{id: &1["id"], label: Emphasis.lower([&1["label"]])}),
      ending: if("finale" in passage["tags"], do: passage["name"]),
      done: links == [],
      passed: sections |> Enum.drop(-1) |> Enum.map(& &1.passage),
      title: story.title
    }
  end

  # -- rendering -----------------------------------------------------------------

  # Walks the body in order. Modifiers switch what follows on or off until
  # the next one: `[if]` … `[else]` … `[end]`.
  defp render(passage, story, w) do
    first_visit? = w.visits[passage["name"]] == 1
    init = %{blocks: [], links: [], show: true, last_if: true, w: w}

    acc =
      Enum.reduce(passage["body"], init, fn node, acc ->
        node(node, acc, story, first_visit?)
      end)

    {Enum.reverse(acc.blocks), Enum.reverse(acc.links), acc.w}
  end

  defp node(%{"type" => "modifier", "parts" => parts}, acc, story, first_visit?) do
    Enum.reduce(parts, acc, fn part, acc -> modifier(part, acc, story, first_visit?) end)
  end

  defp node(%{"type" => "link"} = link, %{show: true} = acc, story, _) do
    {when_ok, w} = holds(link["when"], story, acc.w)
    {visible, w} = holds(link["hidden_until"], story, w)
    acc = %{acc | w: w}
    if when_ok and visible, do: %{acc | links: [link | acc.links]}, else: acc
  end

  defp node(%{"type" => type} = node, %{show: true} = acc, story, _)
       when type in ["prose", "speech"] do
    {blocks, w} = text_blocks(node, story, acc.w)
    %{acc | blocks: Enum.reverse(blocks) ++ acc.blocks, w: w}
  end

  defp node(_node, acc, _story, _), do: acc

  defp modifier(%{"name" => name} = part, acc, story, first_visit?) do
    case name do
      "if" ->
        {v, w} = holds(part["when"], story, acc.w)
        %{acc | show: v, last_if: v, w: w}

      "unless" ->
        {v, w} = holds(part["when"], story, acc.w)
        %{acc | show: not v, last_if: not v, w: w}

      "else" ->
        %{acc | show: not acc.last_if}

      "end" ->
        %{acc | show: true, last_if: true}

      "once" ->
        %{acc | show: acc.show and first_visit?}

      "beat" when acc.show ->
        %{acc | blocks: [%{type: :beat, time: part["time"]} | acc.blocks]}

      # `after` delays text; `beat` while hidden shows nothing.
      _ ->
        acc
    end
  end

  defp holds(nil, _story, w), do: {true, w}

  defp holds(expr, story, w) do
    {v, w} = World.eval(expr, story, w)
    {World.truthy?(v), w}
  end

  # A prose or speech node becomes one block, or several when a paragraph is
  # a list (`{list the_list ~ one per line}` is its own block).
  defp text_blocks(node, story, w) do
    {paragraphs, w} =
      Enum.map_reduce(node["paragraphs"], w, fn paragraph, w -> paragraph(paragraph, story, w) end)

    blocks =
      paragraphs
      |> Enum.reject(&(&1 == {:para, []}))
      |> Enum.chunk_by(&elem(&1, 0))
      |> Enum.flat_map(fn
        [{:list, _} | _] = lists ->
          Enum.map(lists, fn {:list, items} -> %{type: :list, items: items} end)

        paras ->
          [text_block(node, Enum.map(paras, &elem(&1, 1)), story, w)]
      end)

    {blocks, w}
  end

  defp text_block(%{"type" => "speech"} = node, paragraphs, story, w) do
    %{
      type: :speech,
      who: node["who"],
      name: World.label(node["who"], story, w),
      direction: node["direction"],
      paragraphs: paragraphs
    }
  end

  defp text_block(_node, paragraphs, _story, _w), do: %{type: :prose, paragraphs: paragraphs}

  defp paragraph([%{"insert" => "list", "list" => list}], story, w) do
    {{:list, list_items(list, story, w)}, w}
  end

  defp paragraph(parts, story, w) do
    {parts, w} = Enum.flat_map_reduce(parts, w, &part(&1, story, &2))
    parts = if Enum.all?(parts, &(&1 == "")), do: [], else: Emphasis.lower(parts)
    {{:para, parts}, w}
  end

  defp part(text, _story, w) when is_binary(text), do: {[text], w}

  defp part(%{"value" => expr}, story, w) do
    {v, w} = World.eval(expr, story, w)
    {[World.show(v, story, w)], w}
  end

  defp part(%{"insert" => "list", "list" => list}, story, w) do
    {[list_items(list, story, w) |> Enum.map_join(", ", & &1.text)], w}
  end

  # Sounds have no text of their own.
  defp part(%{"insert" => _}, _story, w), do: {[], w}

  defp list_items(list, story, w) do
    for entry <- Map.get(w.lists, list, []) do
      %{
        text: entry.label || World.label(entry.id, story, w),
        mark: entry.mark,
        struck: entry.struck
      }
    end
  end

  # -- effects -------------------------------------------------------------------

  defp apply_effect(%{"when" => condition} = effect, clauses, story, w) when condition != nil do
    case holds(condition, story, w) do
      {true, w} -> apply_effect(Map.delete(effect, "when"), clauses, story, w)
      {false, w} -> w
    end
  end

  defp apply_effect(%{"do" => "set", "target" => target, "value" => value}, _, story, w) do
    {v, w} = World.eval(value, story, w)
    put_in(w.vals[World.key(target, story, w)], v)
  end

  defp apply_effect(%{"do" => "add", "args" => args}, clauses, _story, w) do
    {before_to, ["to", list | rest]} = Enum.split_while(args, &(&1 != "to"))

    mark =
      case rest do
        ["as", mark | _] -> mark
        _ -> nil
      end

    entries =
      if(before_to == [], do: [], else: [entry(before_to, mark)]) ++
        Enum.map(clauses, &entry(&1["words"] || [], nil))

    update_in(w.lists, &Map.update(&1, list, entries, fn existing -> existing ++ entries end))
  end

  defp apply_effect(%{"do" => verb, "args" => [item, _on, list]}, _, _story, w)
       when verb in ["strike", "remove"] do
    update_in(w.lists[list], fn entries ->
      entries = entries || []

      if verb == "remove",
        do: Enum.reject(entries, &(&1.id == item)),
        else: Enum.map(entries, &if(&1.id == item, do: %{&1 | struck: true}, else: &1))
    end)
  end

  defp apply_effect(%{"do" => "move", "args" => args}, _, _story, w) do
    put_in(w.vals["#{hd(args)}.place"], {:id, List.last(args)})
  end

  # A list entry from an effect's words: `naming: "naming a comrade…"`.
  defp entry([id | rest], mark) do
    label =
      case rest do
        [%{"str" => label} | _] -> label
        _ -> nil
      end

    %{id: String.trim_trailing(id, ":"), label: label, mark: mark, struck: false}
  end
end
