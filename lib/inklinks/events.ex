defmodule Inklinks.Events do
  @moduledoc """
  The event log: append to a stream, read it back. Nothing else.

  A **stream** is one reading (later, also a reader's own stream). Every event
  in it has a `stream_version`: 1, 2, 3… with no gaps. Appending names the
  version the caller last saw (`expected`), and fails if someone else wrote
  in between. That is optimistic concurrency, enforced by a unique
  constraint in the database, so it holds even across nodes.

  The log only grows. The database refuses UPDATE, DELETE and TRUNCATE on
  the table (see the migration), and this module offers no way to ask.

      stream = %{type: "reading", id: reading_id, reader_id: r, inklink_id: "ex3"}
      {:ok, [event]} = Events.append(stream, 0, [%{type: "reading_started", data: %{seed: 1}}])
      {:ok, _} = Events.append(stream, 1, [%{type: "link_taken", data: %{link: "arrival#3"}}])
      {:error, {:wrong_expected_version, 2}} = Events.append(stream, 1, [...])
  """
  import Ecto.Query

  alias Inklinks.Events.Event
  alias Inklinks.Repo

  @type stream :: %{
          required(:type) => String.t(),
          required(:id) => Ecto.UUID.t(),
          required(:reader_id) => Ecto.UUID.t(),
          optional(:inklink_id) => String.t() | nil
        }

  @typedoc "An event to append. `occurred_at` defaults to now."
  @type new_event :: %{
          required(:type) => String.t(),
          optional(:data) => map(),
          optional(:type_version) => pos_integer(),
          optional(:actor) => String.t(),
          optional(:occurred_at) => DateTime.t()
        }

  @type expected :: non_neg_integer() | :any

  @stream_types ~w(reading reader)
  @type_format ~r/^[a-z][a-z0-9_]*$/

  @doc """
  Appends `events` to `stream`, in order, after version `expected`.

  `expected` is the stream's version as the caller last saw it: `0` for a
  stream that does not exist yet, or `:any` to skip the check.

  Returns the stored events, or:

    * `{:error, {:wrong_expected_version, actual}}` when the stream has
      moved on (or was not at `expected`);
    * `{:error, {:invalid, reason}}` when an event is malformed. Nothing is
      written: an append is all or nothing.
  """
  @spec append(stream(), expected(), [new_event()]) ::
          {:ok, [Event.t()]}
          | {:error, {:wrong_expected_version, non_neg_integer()}}
          | {:error, {:invalid, term()}}
  def append(stream, expected, events) when is_list(events) do
    with :ok <- validate_stream(stream),
         :ok <- validate_events(events) do
      case Repo.transaction(fn -> insert(stream, expected, events) end) do
        {:ok, stored} ->
          {:ok, stored}

        # Read the version after the transaction: inside it, a failed insert
        # has aborted the transaction and no further query would run.
        {:error, :conflict} ->
          {:error, {:wrong_expected_version, version(stream.id)}}
      end
    end
  end

  @doc "The stream's current version: how many events it holds (0 if none)."
  @spec version(Ecto.UUID.t()) :: non_neg_integer()
  def version(stream_id) do
    Event
    |> where(stream_id: ^stream_id)
    |> select([e], coalesce(max(e.stream_version), 0))
    |> Repo.one()
  end

  @doc "Every event in one stream, in stream order."
  @spec read_stream(Ecto.UUID.t()) :: [Event.t()]
  def read_stream(stream_id) do
    Event
    |> where(stream_id: ^stream_id)
    |> order_by(:stream_version)
    |> Repo.all()
  end

  @doc """
  Events across all streams in global order, after `position` (exclusive).
  For projections that catch up from where they left off.
  """
  @spec read_all(non_neg_integer(), pos_integer()) :: [Event.t()]
  def read_all(after_position \\ 0, limit \\ 1_000) do
    Event
    |> where([e], e.position > ^after_position)
    |> order_by(:position)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "How many events the log holds."
  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(Event, :count)

  # -- writing ---------------------------------------------------------------

  defp insert(stream, expected, events) do
    current = version(stream.id)
    start = if expected == :any, do: current, else: expected

    # Checked even for an empty batch: appending nothing still asserts that
    # the writer has seen the latest event.
    if expected != :any and expected != current do
      Repo.rollback(:conflict)
    end

    store(stream, start, events)
  end

  defp store(_stream, _start, []), do: []

  defp store(stream, start, events) do
    now = DateTime.utc_now()

    rows =
      events
      |> Enum.with_index(start + 1)
      |> Enum.map(fn {event, version} -> row(stream, event, version, now) end)

    try do
      {_count, stored} = Repo.insert_all(Event, rows, returning: true)
      Enum.sort_by(stored, & &1.stream_version)
    rescue
      # Someone appended between our read of `current` and our insert: the
      # unique (stream_id, stream_version) constraint caught it.
      e in Postgrex.Error ->
        if e.postgres.code == :unique_violation do
          Repo.rollback(:conflict)
        else
          reraise e, __STACKTRACE__
        end
    end
  end

  defp row(stream, event, version, now) do
    %{
      id: Ecto.UUID.generate(version: 7),
      stream_type: stream.type,
      stream_id: stream.id,
      stream_version: version,
      type: event.type,
      type_version: Map.get(event, :type_version, 1),
      actor: Map.get(event, :actor, "platform"),
      data: Map.get(event, :data, %{}),
      reader_id: stream.reader_id,
      inklink_id: Map.get(stream, :inklink_id),
      occurred_at: Map.get(event, :occurred_at, now)
    }
  end

  # -- validation ------------------------------------------------------------
  # The database checks these too; checking here gives a clear error instead
  # of a constraint name, and keeps a bad batch from half-starting.

  defp validate_stream(%{type: type, id: id, reader_id: reader_id})
       when type in @stream_types do
    with {:ok, _} <- Ecto.UUID.cast(id),
         {:ok, _} <- Ecto.UUID.cast(reader_id) do
      :ok
    else
      :error -> {:error, {:invalid, :stream_ids_must_be_uuids}}
    end
  end

  defp validate_stream(_), do: {:error, {:invalid, :bad_stream}}

  defp validate_events(events) do
    case Enum.find(events, &(not valid_event?(&1))) do
      nil -> :ok
      bad -> {:error, {:invalid, {:bad_event, bad}}}
    end
  end

  defp valid_event?(%{type: type} = event) when is_binary(type) do
    Regex.match?(@type_format, type) and
      Map.get(event, :actor, "platform") in ~w(linker engine platform) and
      is_map(Map.get(event, :data, %{})) and
      match?(v when is_integer(v) and v >= 1, Map.get(event, :type_version, 1))
  end

  defp valid_event?(_), do: false
end
