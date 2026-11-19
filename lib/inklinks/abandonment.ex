defmodule Inklinks.Abandonment do
  @moduledoc """
  Readings left unfinished, inferred from the log.

  Nobody says "I'm stopping here", so the platform infers it: a reading
  with no `reading_finished`, whose last event is older than
  `:abandon_after` (default one day), gets a `reading_abandoned`. Its
  `occurred_at` is the moment of that last event, when the Linker actually
  stopped; `recorded_at` says when it was inferred.

  If the Linker comes back and acts again, `Inklinks.Reading` records a
  `reading_resumed` first, with how long they were away. Abandonment is an
  inference, never a verdict.

  `sweep/1` does the work; `Inklinks.Abandonment.Sweeper` runs it every
  `:sweep_every` milliseconds (not in tests, which call `sweep/1`).
  """
  alias Inklinks.{Events, Repo}

  @default_after 24 * 60 * 60

  # One row per unfinished reading whose last event is older than the cutoff
  # and is not already an inferred abandonment. A full scan grouped by
  # stream: fine for the slice; a readings projection is the place for it
  # once the log is large.
  @stale """
  SELECT stream_id,
         max(stream_version) AS version,
         max(occurred_at) AS last_at,
         (array_agg(type ORDER BY stream_version DESC))[1] AS last_type,
         (array_agg(data->>'nib' ORDER BY stream_version DESC)
            FILTER (WHERE type = 'nib_shown'))[1] AS last_nib,
         (array_agg(reader_id))[1] AS reader_id,
         (array_agg(inklink_id))[1] AS inklink_id
  FROM events
  WHERE stream_type = 'reading'
  GROUP BY stream_id
  HAVING max(occurred_at) < $1
     AND NOT bool_or(type = 'reading_finished')
     AND (array_agg(type ORDER BY stream_version DESC))[1] <> 'reading_abandoned'
  """

  @doc """
  Records `reading_abandoned` for every reading idle since before `now`
  less `:abandon_after` seconds. Returns how many it recorded. A Linker who
  acts during the sweep wins: their append moves the stream on, and the
  sweep's append for that reading is refused.
  """
  @spec sweep(DateTime.t()) :: non_neg_integer()
  def sweep(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -abandon_after(), :second)

    @stale
    |> Repo.query!([cutoff])
    |> Map.fetch!(:rows)
    |> Enum.count(fn [stream_id, version, last_at, _type, nib, reader_id, inklink_id] ->
      stream = %{
        type: "reading",
        id: Ecto.UUID.load!(stream_id),
        reader_id: Ecto.UUID.load!(reader_id),
        inklink_id: inklink_id
      }

      abandoned = %{
        type: "reading_abandoned",
        occurred_at: last_at,
        data: %{"nib" => nib, "idle_seconds" => DateTime.diff(now, last_at)}
      }

      match?(
        {:ok, _},
        Events.append(stream, version, [Inklinks.Events.Catalog.stamp!(abandoned)])
      )
    end)
  end

  defp abandon_after, do: Application.get_env(:inklinks, :abandon_after, @default_after)

  defmodule Sweeper do
    @moduledoc "Runs `Inklinks.Abandonment.sweep/1` every `:sweep_every` ms."
    use GenServer

    def start_link(every), do: GenServer.start_link(__MODULE__, every, name: __MODULE__)

    @impl true
    def init(every) do
      schedule(every)
      {:ok, every}
    end

    @impl true
    def handle_info(:sweep, every) do
      Inklinks.Abandonment.sweep()
      schedule(every)
      {:noreply, every}
    end

    defp schedule(every), do: Process.send_after(self(), :sweep, every)
  end
end
