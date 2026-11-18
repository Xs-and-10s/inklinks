defmodule Inklinks.Reading do
  @moduledoc """
  One Linker's reading of one Inklink: a stream in the event log.

  The log is the record. A reading's engine state is rebuilt from it on
  every load: `start/2` with the seed `reading_started` recorded, then
  `take/3` for each `link_taken`, in order. The engine is deterministic, so
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
  defstruct [:id, :reader_id, :inklink_id, :loaded, :state, :seed, version: 0]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          reader_id: Ecto.UUID.t(),
          inklink_id: String.t(),
          loaded: Stories.loaded(),
          state: Engine.state(),
          seed: integer(),
          version: non_neg_integer()
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
        seed: seed
      }

      view = view(reading)

      started = %{
        type: "reading_started",
        data: %{
          "seed" => seed,
          "ir" => loaded.entry.ir,
          "ir_sha256" => loaded.sha256,
          "engine" => inspect(Engine.impl()),
          "inquests" => Engine.call(:meta, [loaded.story]).inquests
        }
      }

      append(reading, [started | shown(view)])
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
      version: first.stream_version
    }

    Enum.reduce_while(rest, {:ok, reading}, fn event, {:ok, reading} ->
      case redo(reading, event) do
        {:ok, state} -> {:cont, {:ok, %{reading | state: state, version: event.stream_version}}}
        {:error, reason} -> {:halt, {:error, {:replay_failed, event.stream_version, reason}}}
      end
    end)
  end

  # Only the events that moved the reading change the engine's state.
  defp redo(reading, %Event{type: "link_taken", data: %{"link" => link}}),
    do: Engine.call(:take, [reading.loaded.story, reading.state, link])

  defp redo(reading, _event), do: {:ok, reading.state}

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
         {:ok, state} <- Engine.call(:take, [reading.loaded.story, reading.state, link_id]) do
      taken = %{
        type: "link_taken",
        data: %{"link" => link_id, "nib" => before.nib, "label" => plain(label)}
      }

      reading = %{reading | state: state}
      append(reading, [taken | shown(view(reading))])
    end
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

  # What showing a view records: the Nib, and when it ends something.
  defp shown(view) do
    nib = %{
      type: "nib_shown",
      data: %{
        "nib" => view.nib,
        "passed" => view.passed,
        "links" => Enum.map(view.links, & &1.id)
      }
    }

    ending = view.ending && %{type: "ending_reached", data: %{"ending" => view.ending}}
    finished = view.done && %{type: "reading_finished", data: %{"ending" => view.ending}}

    Enum.reject([nib, ending, finished], &(&1 in [nil, false]))
  end

  defp append(reading, events) do
    stream = %{
      type: "reading",
      id: reading.id,
      reader_id: reading.reader_id,
      inklink_id: reading.inklink_id
    }

    case Events.append(stream, reading.version, events) do
      {:ok, stored} -> {:ok, %{reading | version: List.last(stored).stream_version}}
      {:error, reason} -> {:error, reason}
    end
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
