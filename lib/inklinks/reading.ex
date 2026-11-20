defmodule Inklinks.Reading do
  @moduledoc """
  One Linker's reading of one Inklink: a stream in the event log.

  The log is the record. A reading's engine state is rebuilt from it on
  every load: `start/2` with the seed `reading_started` recorded, then
  `take_link/3` for each `link_taken`, in order. The engine is deterministic, so
  this always arrives where the Linker left off. (Rebuilding per request is
  the simplest thing that works; docs/engine-calls.md says what it costs.)

  Every command appends its events with the version it read, so two tabs
  taking Links at once cannot both win: the loser reloads and shows where
  the reading really is.

  The events, and what each one's `data` holds, are specified in
  docs/events.md.
  """
  import Ecto.Query

  alias Inklinks.{Engine, Events, Repo, Stories}
  alias Inklinks.Events.Event

  @enforce_keys [:id, :reader_id, :inklink_id]
  defstruct [
    :id,
    :reader_id,
    :inklink_id,
    :loaded,
    :state,
    :seed,
    version: 0,
    # Inquests (see Inklinks.Inquest): the budget the reading started with,
    # how many forks it has taken, and where flow D stands on this Nib.
    budget: 0,
    spent: 0,
    inquest: :none,
    looked: %{},
    # Every Nib shown, newest first, with the engine state there: going back
    # for a fork asked from a later Nib starts from one of these.
    nibs: [],
    # Ratings (see Inklinks.Rating): whether the box has been asked for and
    # answered, the last ending reached, and whether the Linker took or
    # declined a fork (which adds "your path" to the box).
    rating: :none,
    ending: nil,
    forked: false,
    # The last event's time, and whether the reading was inferred abandoned.
    last_at: nil,
    abandoned: false,
    # Versions of the Nibs the Linker has said they would change (More…).
    wished: []
  ]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          reader_id: Ecto.UUID.t(),
          inklink_id: String.t(),
          loaded: Stories.loaded(),
          state: Engine.state(),
          seed: integer(),
          version: non_neg_integer(),
          budget: non_neg_integer(),
          spent: non_neg_integer(),
          inquest: :none | :asking | :mode | {:wanting, String.t(), pos_integer() | nil},
          looked: %{String.t() => %{link: String.t(), at: pos_integer() | nil}},
          nibs: [nib_visit()],
          rating: :none | :asking | :done,
          ending: String.t() | nil,
          forked: boolean(),
          last_at: DateTime.t() | nil,
          abandoned: boolean(),
          wished: [pos_integer()]
        }

  @typedoc """
  One Nib shown: the version of its `nib_shown`, the passage, the engine
  state there, and the label of what the Linker chose there (once they have).
  """
  @type nib_visit :: %{
          version: pos_integer(),
          nib: String.t(),
          state: Engine.state(),
          chose: String.t() | nil
        }

  @doc """
  Starts a new reading of an Inklink. Records `reading_started`, then what
  the Linker is shown first. `seed:` fixes the dice, for tests.
  """
  @spec start(Ecto.UUID.t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(reader_id, inklink_id, opts \\ []) do
    with {:ok, loaded} <- Stories.fetch(inklink_id) do
      seed = Keyword.get_lazy(opts, :seed, fn -> :rand.uniform(Bitwise.bsl(1, 62)) end)
      {:ok, state} = Engine.call(:start, [loaded.story, seed])

      reading = %__MODULE__{
        id: Ecto.UUID.generate(version: 7),
        reader_id: reader_id,
        inklink_id: inklink_id,
        loaded: loaded,
        state: state,
        seed: seed,
        budget: Engine.call(:meta, [loaded.story]).inquests
      }

      view = view(reading)

      started = %{
        type: "reading_started",
        data: %{
          "seed" => seed,
          "ir" => loaded.entry.ir,
          "ir_sha256" => loaded.sha256,
          "engine" => inspect(Engine.impl()),
          "inquests" => reading.budget
        }
      }

      record(reading, [started | returned(reader_id, inklink_id)] ++ shown(reading, view))
    end
  end

  # A Linker starting again after finishing a reading of this Inklink.
  defp returned(reader_id, inklink_id) do
    finished =
      from(e in Event,
        where:
          e.reader_id == ^reader_id and e.inklink_id == ^inklink_id and
            e.type == "reading_finished",
        select: e.data["ending"]
      )
      |> Repo.all()

    if finished == [] do
      []
    else
      endings = finished |> Enum.reject(&is_nil/1) |> Enum.uniq()

      [
        %{
          type: "returned_for_another_ending",
          data: %{"readings_finished" => length(finished), "endings_seen" => endings}
        }
      ]
    end
  end

  @doc "Loads a reading for its reader. Anyone else's reading is `:not_found`."
  @spec load(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, t()} | {:error, :not_found | term()}
  def load(reading_id, reader_id) do
    with {:ok, _} <- Ecto.UUID.cast(reading_id),
         [%Event{type: "reading_started", reader_id: ^reader_id} = first | rest] <-
           Events.read_stream(reading_id),
         {:ok, loaded} <- Stories.fetch(first.inklink_id) do
      replay(first, rest, loaded)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  defp replay(first, rest, loaded) do
    seed = first.data["seed"]
    {:ok, state} = Engine.call(:start, [loaded.story, seed])

    reading = %__MODULE__{
      id: first.stream_id,
      reader_id: first.reader_id,
      inklink_id: first.inklink_id,
      loaded: loaded,
      state: state,
      seed: seed,
      version: first.stream_version,
      budget: first.data["inquests"] || 0
    }

    Enum.reduce_while(rest, {:ok, reading}, fn event, {:ok, reading} ->
      case redo(reading, event) do
        {:ok, state} ->
          reading = evolve(%{reading | state: state, version: event.stream_version}, event)
          {:cont, {:ok, reading}}

        {:error, reason} ->
          {:halt, {:error, {:replay_failed, event.stream_version, reason}}}
      end
    end)
  end

  # Only the events that moved the reading change the engine's state.
  defp redo(reading, %Event{type: "link_taken", data: %{"link" => link}}),
    do: Engine.call(:take_link, [reading.loaded.story, reading.state, link])

  defp redo(reading, %Event{type: "fork_taken", data: %{"fork" => fork} = data}),
    do: Engine.call(:take_fork, [reading.loaded.story, state_at(reading, data["back_to"]), fork])

  defp redo(reading, _event), do: {:ok, reading.state}

  # What each event does to the reading's own fields: where flow D stands,
  # which forks were looked at, how many Inquests are spent. Used both when
  # replaying the log and after appending, so live and rebuilt agree.
  defp evolve(reading, %{type: type, data: data} = event) do
    reading = %{reading | last_at: event.occurred_at}

    case type do
      "nib_shown" ->
        visit = %{version: version_of(event), nib: data["nib"], state: reading.state, chose: nil}
        %{reading | inquest: :none, looked: %{}, nibs: [visit | reading.nibs]}

      type when type in ["link_taken", "fork_taken"] ->
        reading =
          if type == "fork_taken",
            do: %{reading | spent: reading.spent + 1, forked: true},
            else: reading

        chosen(reading, data["back_to"], data["label"])

      "inquest_opened" ->
        %{reading | inquest: :asking}

      "inquest_turned_down" ->
        %{reading | inquest: :none}

      "inquest_mode_entered" ->
        %{reading | inquest: :mode}

      "fork_looked" ->
        look = %{link: data["link"], at: data["back_to"]}
        %{reading | looked: Map.put(reading.looked, data["fork"], look)}

      "wanted_instead_opened" ->
        %{reading | inquest: {:wanting, data["link"], data["back_to"]}}

      "inquest_mode_left" ->
        %{reading | inquest: :none}

      "fork_declined" ->
        %{reading | forked: true}

      "ending_reached" ->
        %{reading | ending: data["ending"]}

      "rating_asked" ->
        %{reading | rating: :asking}

      type when type in ["rating_given", "rating_dismissed"] ->
        %{reading | rating: :done}

      "reading_abandoned" ->
        %{reading | abandoned: true}

      "reading_resumed" ->
        %{reading | abandoned: false}

      "change_wished" ->
        %{reading | wished: [data["back_to"] | reading.wished]}

      _ ->
        reading
    end
  end

  defp version_of(%{stream_version: v}), do: v

  # Note what was chosen at a Nib: the current one, or, for a fork asked
  # for from a later Nib, the earlier visit it went back to. Only the first
  # choice counts.
  defp chosen(reading, back_to, label) do
    target = back_to || hd(reading.nibs).version

    nibs =
      Enum.map(reading.nibs, fn
        %{version: ^target, chose: nil} = visit -> %{visit | chose: label}
        visit -> visit
      end)

    %{reading | nibs: nibs}
  end

  @doc """
  The engine state at an earlier Nib, by the version of its `nib_shown`;
  the current state for `nil`.
  """
  @spec state_at(t(), pos_integer() | nil) :: Engine.state()
  def state_at(reading, nil), do: reading.state
  def state_at(reading, version), do: Enum.find(reading.nibs, &(&1.version == version)).state

  @max_earlier 3

  @doc """
  Where an Inquest can look from the current Nib: the Nib itself (`at:
  nil`), then the earlier visits the Linker may go back to, newest first.

  An earlier visit is offered when its passage has forks that may be asked
  for from here (`inquest.from`) and, in that visit's state, a fork can
  actually be taken. Visits where the Linker made the same choice collapse
  into the latest of them (going further back for the same choice only
  costs more), and at most #{@max_earlier} are offered. Each carries `back`:
  how many choices going back would undo.
  """
  @spec places(t()) :: [map()]
  def places(%__MODULE__{nibs: [here | earlier]} = reading) do
    story = reading.loaded.story
    passages = Engine.call(:asked_from, [story, here.nib])

    remote =
      earlier
      |> Enum.with_index(1)
      |> Enum.filter(fn {visit, _} ->
        visit.nib in passages and Engine.call(:forks?, [story, visit.state, here.nib])
      end)
      |> Enum.uniq_by(fn {visit, _} -> {visit.nib, visit.chose} end)
      |> Enum.take(@max_earlier)
      |> Enum.map(fn {visit, back} -> Map.merge(visit, %{at: visit.version, back: back}) end)

    [Map.merge(here, %{at: nil, back: 0}) | remote]
  end

  @doc "Inquests left in this reading: the budget, less the forks taken."
  @spec remaining(t()) :: non_neg_integer()
  def remaining(%__MODULE__{budget: budget, spent: spent}), do: budget - spent

  @doc "What the Linker sees now."
  @spec view(t()) :: Engine.view()
  def view(%__MODULE__{} = reading), do: Engine.call(:view, [reading.loaded.story, reading.state])

  @doc """
  Takes a Link. Only a Link the current view offers is taken; anything else
  is `{:error, :not_offered}`, and nothing is recorded.
  """
  @spec take(t(), String.t()) ::
          {:ok, t()} | {:error, :not_offered | {:wrong_expected_version, non_neg_integer()}}
  def take(%__MODULE__{} = reading, link_id) when is_binary(link_id) do
    before = view(reading)

    with %{label: label} <- Enum.find(before.links, &(&1.id == link_id)) || {:error, :not_offered},
         {:ok, state} <- Engine.call(:take_link, [reading.loaded.story, reading.state, link_id]) do
      taken = %{
        type: "link_taken",
        data: %{"link" => link_id, "nib" => before.nib, "label" => plain(label)}
      }

      # Forks looked at and now declined count as a path, for the ratings box.
      declines? = reading.inquest not in [:none, :asking] and reading.looked != %{}
      reading_after = %{reading | state: state, forked: reading.forked or declines?}

      record(
        reading_after,
        leaving(reading, "took_link") ++ [taken | shown(reading_after, view(reading_after))]
      )
    end
  end

  @doc """
  The events that close flow D when the Linker moves on without a fork:
  each fork looked at is declined, and Inquest mode is left. Nothing when
  the reading is not in Inquest mode.
  """
  @spec leaving(t(), String.t()) :: [map()]
  def leaving(%__MODULE__{inquest: :none}, _reason), do: []
  def leaving(%__MODULE__{inquest: :asking}, _reason), do: []

  def leaving(%__MODULE__{} = reading, reason) do
    nib = view(reading).nib

    declined(reading, reason) ++
      [%{type: "inquest_mode_left", data: %{"nib" => nib, "reason" => reason}}]
  end

  @doc "A `fork_declined` for each fork looked at in this Inquest mode, except `but`."
  @spec declined(t(), String.t(), String.t() | nil) :: [map()]
  def declined(%__MODULE__{} = reading, by, but \\ nil) do
    nib = view(reading).nib

    for {fork, look} <- Enum.sort(reading.looked), fork != but do
      data = %{"nib" => nib, "link" => look.link, "fork" => fork, "by" => by}
      %{type: "fork_declined", data: located(reading, look.at, data)}
    end
  end

  @doc """
  Adds where a fork was asked for, when it was not the current Nib: the
  earlier passage (`at`) and the version of its visit (`back_to`).
  """
  @spec located(t(), pos_integer() | nil, map()) :: map()
  def located(_reading, nil, data), do: data

  def located(reading, version, data) do
    visit = Enum.find(reading.nibs, &(&1.version == version))
    Map.merge(data, %{"at" => visit.nib, "back_to" => version})
  end

  @doc """
  The reader's unfinished reading of an Inklink, if there is one: the latest
  `reading_started` with no `reading_finished` after it.
  """
  @spec current(Ecto.UUID.t(), String.t()) :: Ecto.UUID.t() | nil
  def current(reader_id, inklink_id) do
    finished =
      from f in Event,
        where: f.stream_id == parent_as(:started).stream_id and f.type == "reading_finished"

    from(e in Event,
      as: :started,
      where:
        e.reader_id == ^reader_id and e.inklink_id == ^inklink_id and
          e.type == "reading_started" and not exists(finished),
      order_by: [desc: e.position],
      limit: 1,
      select: e.stream_id
    )
    |> Repo.one()
  end

  # -- recording -----------------------------------------------------------------

  @doc false
  # What showing a view records: the Nib, and when it ends something.
  def shown(reading, view) do
    nib = %{
      type: "nib_shown",
      data: %{
        "nib" => view.nib,
        "passed" => view.passed,
        "links" => Enum.map(view.links, & &1.id),
        # 1 the first time this reading shows this Nib; more is a re-read.
        "visit" => Enum.count(reading.nibs, &(&1.nib == view.nib)) + 1
      }
    }

    ending = view.ending && %{type: "ending_reached", data: %{"ending" => view.ending}}

    ask =
      view.ending && reading.rating == :none && not rated?(reading, view.ending) &&
        %{type: "rating_asked", data: %{"ending" => view.ending, "path" => reading.forked}}

    finished =
      view.done && %{type: "reading_finished", data: %{"ending" => view.ending || reading.ending}}

    Enum.reject([nib, ending, ask, finished], &(&1 in [nil, false]))
  end

  # Has this Linker already rated this ending, in any reading?
  defp rated?(reading, ending) do
    from(e in Event,
      where:
        e.reader_id == ^reading.reader_id and e.inklink_id == ^reading.inklink_id and
          e.type == "rating_given" and fragment("? @> ?", e.data, ^%{"ending" => ending})
    )
    |> Repo.exists?()
  end

  @doc """
  Appends events to the reading's stream, after the version it was loaded
  at, and applies them to the reading. The one way anything is recorded.
  """
  @spec record(t(), [map()]) :: {:ok, t()} | {:error, term()}
  def record(reading, events) do
    stream = %{
      type: "reading",
      id: reading.id,
      reader_id: reading.reader_id,
      inklink_id: reading.inklink_id
    }

    # Every event is checked against the catalogue and stamped with its origin.
    events = Enum.map(resumed(reading) ++ events, &Inklinks.Events.Catalog.stamp!/1)

    case Events.append(stream, reading.version, events) do
      {:ok, stored} ->
        reading = Enum.reduce(stored, reading, &evolve(&2, &1))
        {:ok, %{reading | version: List.last(stored).stream_version}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A reading inferred abandoned that the Linker comes back to: say so first.
  defp resumed(%__MODULE__{abandoned: true} = reading) do
    gap = DateTime.diff(DateTime.utc_now(), reading.last_at)
    # The Nib they left off at: the last one shown, not where this step leads.
    [%{type: "reading_resumed", data: %{"nib" => hd(reading.nibs).nib, "after_seconds" => gap}}]
  end

  defp resumed(_reading), do: []

  @doc ~S"""
  A Link label in quotation marks, for running text, unless it already
  has its own (a line of dialogue does):

      iex> Inklinks.Reading.quoted("Run")
      "“Run”"
      iex> Inklinks.Reading.quoted("“They named me Skittles.”")
      "“They named me Skittles.”"
  """
  @spec quoted(String.t()) :: String.t()
  def quoted(label) do
    if String.first(label) in ~w(“ " ‘ ') and String.last(label) in ~w(” " ’ '),
      do: label,
      else: "“#{label}”"
  end

  @doc "A Link label or paragraph as plain text, for the record."
  @spec plain(Engine.paragraph()) :: String.t()
  def plain(parts) do
    Enum.map_join(parts, fn
      text when is_binary(text) -> text
      %{parts: inner} -> plain(inner)
      _ -> ""
    end)
  end
end
