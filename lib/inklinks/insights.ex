defmodule Inklinks.Insights do
  @moduledoc """
  What an Inker will want to know about an Inklink, read straight from the
  event log. Nothing here is stored: every answer is a query over `events`,
  which is the point. If a question could not be answered this way, the log
  would be missing something.

  These are plain SQL, so they read as the spec does (docs/events.md), and
  they are the first projections a Rust event log would need to support.
  """
  alias Inklinks.Repo

  @doc "Where readers stop: abandoned readings, by the Nib they stopped at."
  @spec stops(String.t()) :: [%{nib: String.t(), readings: integer()}]
  def stops(inklink) do
    rows(
      """
      SELECT data->>'nib', count(*) FROM events
      WHERE inklink_id = $1 AND type = 'reading_abandoned'
      GROUP BY 1 ORDER BY 2 DESC, 1
      """,
      [inklink],
      fn [nib, n] -> %{nib: nib, readings: n} end
    )
  end

  @doc """
  Time per Nib: from `nib_shown` to the Linker's next action (the next event
  whose origin is `linker`), as a median in seconds, over every showing that
  had one. Engine and platform events written in the same moment do not
  count.
  """
  @spec time_per_nib(String.t()) :: [
          %{nib: String.t(), median_seconds: float(), showings: integer()}
        ]
  def time_per_nib(inklink) do
    rows(
      """
      SELECT data->>'nib',
             percentile_cont(0.5) WITHIN GROUP (ORDER BY secs),
             count(*)
      FROM (
        SELECT type, data,
               extract(epoch FROM lead(occurred_at) OVER w - occurred_at)::float AS secs
        FROM events
        WHERE inklink_id = $1 AND (type = 'nib_shown' OR origin = 'linker')
        WINDOW w AS (PARTITION BY stream_id ORDER BY stream_version)
      ) t
      WHERE type = 'nib_shown' AND secs IS NOT NULL
      GROUP BY 1 ORDER BY 1
      """,
      [inklink],
      fn [nib, median, n] -> %{nib: nib, median_seconds: median, showings: n} end
    )
  end

  @doc """
  Re-reads: Nibs shown again within one reading (a hub, or going back), and
  readers who read the Inklink more than once.
  """
  @spec rereads(String.t()) :: %{nibs: [%{nib: String.t(), again: integer()}], readers: integer()}
  def rereads(inklink) do
    nibs =
      rows(
        """
        SELECT data->>'nib', count(*) FROM events
        WHERE inklink_id = $1 AND type = 'nib_shown' AND (data->>'visit')::int > 1
        GROUP BY 1 ORDER BY 2 DESC, 1
        """,
        [inklink],
        fn [nib, n] -> %{nib: nib, again: n} end
      )

    [[readers]] =
      Repo.query!(
        """
        SELECT count(*) FROM (
          SELECT reader_id FROM events
          WHERE inklink_id = $1 AND type = 'reading_started'
          GROUP BY reader_id HAVING count(*) > 1
        ) r
        """,
        [inklink]
      ).rows

    %{nibs: nibs, readers: readers}
  end

  @doc "What happened to each fork: looked at, taken, declined."
  @spec forks(String.t()) :: [
          %{fork: String.t(), looked: integer(), taken: integer(), declined: integer()}
        ]
  def forks(inklink) do
    rows(
      """
      SELECT data->>'fork',
             count(*) FILTER (WHERE type = 'fork_looked'),
             count(*) FILTER (WHERE type = 'fork_taken'),
             count(*) FILTER (WHERE type = 'fork_declined')
      FROM events
      WHERE inklink_id = $1 AND type IN ('fork_looked', 'fork_taken', 'fork_declined')
      GROUP BY 1 ORDER BY 1
      """,
      [inklink],
      fn [fork, l, t, d] -> %{fork: fork, looked: l, taken: t, declined: d} end
    )
  end

  @doc """
  What readers asked for, in their words: Inquest requests (and whether they
  were turned down), "what I wanted instead", and moments they would change.
  """
  @spec requests(String.t()) :: [
          %{kind: String.t(), nib: String.t(), text: String.t() | nil, outcome: String.t() | nil}
        ]
  def requests(inklink) do
    rows(
      """
      SELECT type, data->>'nib', data->>'text',
             CASE type
               WHEN 'inquest_submitted' THEN
                 (SELECT coalesce(n.data->>'reason', 'inquest_mode')
                  FROM events n
                  WHERE n.stream_id = e.stream_id AND n.stream_version = e.stream_version + 1)
             END
      FROM events e
      WHERE inklink_id = $1
        AND type IN ('inquest_submitted', 'wanted_instead_submitted', 'change_wished')
      ORDER BY position
      """,
      [inklink],
      fn [type, nib, text, outcome] -> %{kind: type, nib: nib, text: text, outcome: outcome} end
    )
  end

  @doc "Ratings by ending: how many, and the mean of each score."
  @spec ratings(String.t()) :: [map()]
  def ratings(inklink) do
    rows(
      """
      SELECT data->>'ending', count(*),
             avg((data->>'ending_score')::int)::float,
             avg((data->>'inklink_score')::int)::float,
             avg((data->>'path_score')::int)::float
      FROM events
      WHERE inklink_id = $1 AND type = 'rating_given'
      GROUP BY 1 ORDER BY 1
      """,
      [inklink],
      fn [ending, n, e, i, p] ->
        %{ending: ending, ratings: n, ending_score: e, inklink_score: i, path_score: p}
      end
    )
  end

  @doc """
  Returns: readings started after finishing one, and readers who have now
  reached more than one ending.
  """
  @spec returns(String.t()) :: %{returns: integer(), readers_with_several_endings: integer()}
  def returns(inklink) do
    [[returns, several]] =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM events
           WHERE inklink_id = $1 AND type = 'returned_for_another_ending'),
          (SELECT count(*) FROM (
             SELECT reader_id FROM events
             WHERE inklink_id = $1 AND type = 'ending_reached'
             GROUP BY reader_id HAVING count(DISTINCT data->>'ending') > 1) r)
        """,
        [inklink]
      ).rows

    %{returns: returns, readers_with_several_endings: several}
  end

  defp rows(sql, params, fun), do: Repo.query!(sql, params).rows |> Enum.map(fun)
end
