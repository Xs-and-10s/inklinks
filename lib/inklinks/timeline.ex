defmodule Inklinks.Timeline do
  @moduledoc """
  A reading's path, as a tree: one node per Nib shown, in the order the
  Linker saw them. A projection of the log; nothing here is stored.

  **The tree.** Each Nib shown hangs from the Nib its Link or fork was
  taken at: the one before it, or, for a fork that went back
  (`fork_taken.back_to`), the earlier visit it went back to. So a reading
  branches exactly where an Inquest went back, and the path the Linker
  left stays in the tree. (Rewinds, once games have them, branch the same
  way; `via.kind` is where a third kind goes.)

  **The live path** runs from the first Nib to the one shown last: where
  the Linker is, or the ending they reached. Everything off it is a path
  they left.

  **Lanes**, for drawing it top to bottom on a phone, like `git log
  --graph`: the live path is lane 0, a straight line. A path the Linker
  left takes the next lane to the right, from the row it branched at. A
  reading has at most as many branches as Inquests, so it stays narrow.

  **Spoilers.** A row lists what was offered there and not taken: the
  offered Links (the Linker saw them all) and the forks they looked at.
  Never a fork they did not look at.
  """

  alias Inklinks.{Engine, Events, Reading}

  @type kind :: :link | :fork

  @type line :: %{
          lane: non_neg_integer(),
          seg: :through | :top | :bottom | :elbow,
          from: non_neg_integer(),
          kind: kind(),
          live: boolean()
        }

  @type row :: %{
          version: pos_integer(),
          nib: String.t(),
          lane: non_neg_integer(),
          live: boolean(),
          parent: pos_integer() | nil,
          excerpt: String.t(),
          ending: String.t() | nil,
          via:
            nil | %{kind: kind(), label: String.t(), instead: String.t() | nil, back: boolean()},
          not_taken: [%{kind: kind(), label: String.t()}],
          went_back: boolean(),
          here: boolean(),
          lines: [line()]
        }

  @type t :: %__MODULE__{
          title: String.t(),
          rows: [row()],
          lanes: pos_integer(),
          done: boolean(),
          inquests: non_neg_integer()
        }

  defstruct [:title, rows: [], lanes: 1, done: false, inquests: 0]

  @excerpt 90

  @doc "The timeline of a loaded reading."
  @spec build(Reading.t()) :: t()
  def build(%Reading{} = reading) do
    story = reading.loaded.story
    events = Events.read_stream(reading.id)
    views = Map.new(reading.nibs, &{&1.version, Engine.call(:view, [story, &1.state])})

    nodes = nodes(events)
    live = live(nodes)
    nodes = Enum.map(nodes, &Map.put(&1, :live, MapSet.member?(live, &1.version)))
    lanes = lanes(nodes)
    last = List.last(nodes)
    done = views[last.version].done

    rows =
      for node <- nodes do
        view = views[node.version]
        parent_view = node.parent && views[node.parent]

        %{
          version: node.version,
          nib: node.nib,
          lane: lanes[node.version],
          live: node.live,
          parent: node.parent,
          excerpt: excerpt(view),
          ending: view.ending,
          via: via(node.action, parent_view),
          not_taken: if(node == last and not done, do: [], else: not_taken(node, nodes, view)),
          went_back: node.went_back,
          here: node == last and not done
        }
      end

    %__MODULE__{
      title: Reading.view(reading).title,
      rows: lines(rows),
      lanes: (lanes |> Map.values() |> Enum.max()) + 1,
      done: done,
      inquests: reading.spent
    }
  end

  # -- the tree ----------------------------------------------------------------

  # One node per `nib_shown`, with the action that led to it, its parent,
  # the forks looked at from it, and whether an Inquest went back from it.
  defp nodes(events) do
    {nodes, _} =
      Enum.reduce(events, {[], %{current: nil, action: nil}}, fn event, {nodes, at} ->
        case event do
          %{type: "nib_shown", stream_version: v, data: %{"nib" => nib}} ->
            parent = at.action && at.action.from

            node = %{
              version: v,
              nib: nib,
              parent: parent,
              action: at.action,
              looked: [],
              went_back: false
            }

            {[node | nodes], %{current: v, action: nil}}

          %{type: "link_taken", data: d} ->
            action = %{
              kind: :link,
              id: d["link"],
              label: d["label"],
              from: at.current,
              back: false
            }

            {nodes, %{at | action: action}}

          %{type: "fork_taken", data: d} ->
            from = d["back_to"] || at.current
            back = d["back_to"] != nil

            action = %{
              kind: :fork,
              id: d["fork"],
              label: d["label"],
              instead: d["link"],
              from: from,
              back: back
            }

            nodes = if back, do: update(nodes, at.current, &%{&1 | went_back: true}), else: nodes
            {nodes, %{at | action: action}}

          %{type: "fork_looked", data: d} ->
            look = %{id: d["fork"], label: d["label"]}
            {update(nodes, d["back_to"] || at.current, &%{&1 | looked: [look | &1.looked]}), at}

          _ ->
            {nodes, at}
        end
      end)

    Enum.reverse(nodes)
  end

  defp update(nodes, version, fun),
    do: Enum.map(nodes, fn node -> if node.version == version, do: fun.(node), else: node end)

  defp live(nodes) do
    parents = Map.new(nodes, &{&1.version, &1.parent})

    Stream.iterate(List.last(nodes).version, &parents[&1])
    |> Enum.take_while(& &1)
    |> MapSet.new()
  end

  # The live path is lane 0. A child that is not live continues its
  # parent's lane when it is that parent's first child off the live path;
  # any other child opens the next lane.
  defp lanes(nodes) do
    {lanes, _, _} =
      Enum.reduce(nodes, {%{}, 0, MapSet.new()}, fn node, {lanes, top, continued} ->
        cond do
          node.live ->
            {Map.put(lanes, node.version, 0), top, continued}

          node.parent && not live?(nodes, node.parent) &&
              not MapSet.member?(continued, node.parent) ->
            lane = lanes[node.parent]
            {Map.put(lanes, node.version, lane), top, MapSet.put(continued, node.parent)}

          true ->
            {Map.put(lanes, node.version, top + 1), top + 1, MapSet.put(continued, node.parent)}
        end
      end)

    lanes
  end

  defp live?(nodes, version), do: Enum.find(nodes, &(&1.version == version)).live

  # -- what each row says --------------------------------------------------------

  defp via(nil, _), do: nil

  defp via(action, parent_view) do
    instead =
      action[:instead] &&
        Enum.find_value(parent_view.links, fn link ->
          link.id == action.instead && Reading.plain(link.label)
        end)

    %{kind: action.kind, label: action.label, instead: instead, back: action.back}
  end

  # Offered there and not taken: the offered Links, less any taken from
  # this Nib or stood in for by a fork taken from it; then the forks looked
  # at from this Nib and not taken. Never a fork not looked at.
  defp not_taken(node, nodes, view) do
    taken = for n <- nodes, n.parent == node.version, n.action, do: n.action

    taken_ids = MapSet.new(taken, & &1.id)
    stood_in = MapSet.new(for(a <- taken, a.kind == :fork, do: a.instead))

    links =
      for link <- view.links,
          not MapSet.member?(taken_ids, link.id),
          not MapSet.member?(stood_in, link.id),
          do: %{kind: :link, label: Reading.plain(link.label)}

    forks =
      for look <- node.looked |> Enum.reverse() |> Enum.uniq_by(& &1.id),
          not MapSet.member?(taken_ids, look.id),
          do: %{kind: :fork, label: look.label}

    links ++ forks
  end

  defp excerpt(view) do
    text =
      view.ink
      |> Enum.flat_map(& &1.blocks)
      |> Enum.find_value("", fn
        %{paragraphs: [first | _]} -> Reading.plain(first)
        _ -> nil
      end)
      |> String.trim()

    if String.length(text) <= @excerpt do
      text
    else
      cut = String.slice(text, 0, @excerpt)
      (cut |> String.replace(~r/\s+\S*$/u, "") |> String.trim_trailing(",;:—– ")) <> "…"
    end
  end

  # -- lines -------------------------------------------------------------------

  # What to draw in each row's graph cell. An edge from a parent to a child
  # runs in the child's lane: an elbow out of the parent's dot (or a
  # straight segment below it, in the same lane), through the rows between,
  # and into the child's dot from above.
  defp lines(rows) do
    index = rows |> Enum.with_index() |> Map.new(fn {row, i} -> {row.version, i} end)

    edges =
      for row <- rows, row.parent do
        parent = Enum.at(rows, index[row.parent])

        %{
          from_row: index[row.parent],
          to_row: index[row.version],
          lane: row.lane,
          from: parent.lane,
          kind: row.via.kind,
          live: row.live
        }
      end

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, i} ->
      lines =
        for e <- edges, seg = seg(e, i), seg != nil do
          %{lane: e.lane, seg: seg, from: e.from, kind: e.kind, live: e.live}
        end

      Map.put(row, :lines, lines)
    end)
  end

  defp seg(%{from_row: i, lane: lane, from: lane}, i), do: :bottom
  defp seg(%{from_row: i}, i), do: :elbow
  defp seg(%{to_row: i}, i), do: :top
  defp seg(%{from_row: a, to_row: b}, i) when a < i and i < b, do: :through
  defp seg(_, _), do: nil
end
