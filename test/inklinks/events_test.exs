defmodule Inklinks.EventsTest do
  @moduledoc """
  The event log, as behaviour: what a writer may do, what the log refuses,
  and the invariants that hold whatever sequence of writes happens.
  """
  use Inklinks.DataCase, async: true
  use ExUnitProperties

  alias Inklinks.Events
  alias Inklinks.Repo

  # -- scenarios -------------------------------------------------------------

  describe "appending to a new reading" do
    test "stores the events at versions 1, 2, 3, in the order given" do
      # Given a reading no one has written to
      stream = reading()

      # When three events are appended, expecting version 0
      {:ok, stored} =
        Events.append(stream, 0, [
          %{type: "reading_started", data: %{"seed" => 7}},
          %{type: "nib_shown", data: %{"nib" => "arrival"}},
          %{type: "link_taken", data: %{"link" => "arrival#3"}}
        ])

      # Then they come back at versions 1..3, with their data
      assert Enum.map(stored, & &1.stream_version) == [1, 2, 3]

      assert Enum.map(Events.read_stream(stream.id), & &1.type) ==
               ~w(reading_started nib_shown link_taken)

      assert hd(stored).data == %{"seed" => 7}
      assert Events.version(stream.id) == 3
    end
  end

  describe "a writer who has not seen the latest event" do
    test "is turned away with the stream's real version, and writes nothing" do
      # Given a reading at version 2
      stream = reading()
      {:ok, _} = Events.append(stream, 0, [event(), event()])

      # When a writer appends expecting version 1
      result = Events.append(stream, 1, [event()])

      # Then the append fails, naming version 2, and the stream is unchanged
      assert result == {:error, {:wrong_expected_version, 2}}
      assert Events.version(stream.id) == 2
    end
  end

  describe "a batch with one malformed event" do
    test "writes none of the batch" do
      stream = reading()

      assert {:error, {:invalid, {:bad_event, _}}} =
               Events.append(stream, 0, [event(), %{type: "Not A Type"}])

      assert Events.read_stream(stream.id) == []
    end
  end

  describe "the database itself" do
    setup do
      stream = reading()
      {:ok, _} = Events.append(stream, 0, [event()])
      :ok
    end

    test "refuses UPDATE" do
      assert_refused("UPDATE events SET type = 'tampered'")
    end

    test "refuses DELETE" do
      assert_refused("DELETE FROM events")
    end

    test "refuses TRUNCATE" do
      assert_refused("TRUNCATE events")
    end

    test "refuses a second event at the same stream version" do
      stream = reading()
      {:ok, [first]} = Events.append(stream, 0, [event()])

      assert_raise Postgrex.Error, ~r/unique/, fn ->
        Repo.transaction(fn ->
          Repo.query!(
            """
            INSERT INTO events (id, stream_type, stream_id, stream_version, type, reader_id, occurred_at)
            VALUES ($1, 'reading', $2, 1, 'forged', $3, now())
            """,
            [uuid_bin(), uuid_bin(first.stream_id), uuid_bin(first.reader_id)]
          )
        end)
      end
    end
  end

  # -- properties ------------------------------------------------------------

  describe "whatever anyone tries" do
    property "the log only ever grows, and no stored event changes" do
      check all(ops <- list_of(operation(), min_length: 1, max_length: 25), max_runs: 50) do
        stream = reading()

        Enum.reduce(ops, snapshot(), fn op, before ->
          attempt(op, stream)
          now = snapshot()

          # Never fewer events…
          assert map_size(now) >= map_size(before)
          # …and every event seen before is still there, unchanged.
          assert Map.take(now, Map.keys(before)) == before
          now
        end)
      end
    end
  end

  describe "a stream's versions" do
    property "run 1, 2, 3… without gaps, in the order the events were appended" do
      check all(
              batches <- list_of(list_of(new_event(), max_length: 4), max_length: 8),
              stale <- list_of(boolean(), length: length(batches)),
              max_runs: 50
            ) do
        stream = reading()

        appended =
          Enum.zip(batches, stale)
          |> Enum.reduce([], fn {batch, stale?}, acc ->
            expected = length(acc)

            if stale? and expected > 0 do
              # A stale writer is refused and changes nothing.
              assert {:error, {:wrong_expected_version, ^expected}} =
                       Events.append(stream, expected - 1, batch)

              acc
            else
              {:ok, _} = Events.append(stream, expected, batch)
              acc ++ batch
            end
          end)

        stored = Events.read_stream(stream.id)
        assert Enum.map(stored, & &1.stream_version) == Enum.to_list(1..length(appended)//1)
        assert Enum.map(stored, &{&1.type, &1.data}) == Enum.map(appended, &{&1.type, &1.data})
      end
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp reading do
    %{
      type: "reading",
      id: Ecto.UUID.generate(version: 7),
      reader_id: Ecto.UUID.generate(version: 7),
      inklink_id: "ex3-the-fall-of-the-old-regime"
    }
  end

  defp event, do: %{type: "nib_shown", data: %{"nib" => "arrival"}}

  # What a writer, honest or not, might try.
  defp operation do
    one_of([
      tuple({constant(:append), list_of(new_event(), min_length: 1, max_length: 3)}),
      constant(:append_stale),
      constant(:append_invalid),
      member_of([
        {:sql, "UPDATE events SET data = '{}'::jsonb"},
        {:sql, "UPDATE events SET stream_version = stream_version + 100"},
        {:sql, "DELETE FROM events WHERE position = (SELECT max(position) FROM events)"},
        {:sql, "DELETE FROM events"},
        {:sql, "TRUNCATE events"}
      ])
    ])
  end

  defp new_event do
    gen all(
          type <- event_type(),
          data <-
            map_of(string(:alphanumeric, min_length: 1, max_length: 8), json_scalar(),
              max_length: 3
            )
        ) do
      %{type: type, data: data}
    end
  end

  defp event_type do
    gen all(
          first <- string(?a..?z, length: 1),
          rest <- string([?a..?z, ?0..?9, ?_], max_length: 12)
        ) do
      first <> rest
    end
  end

  defp json_scalar do
    one_of([string(:printable, max_length: 20), integer(), boolean()])
  end

  defp attempt({:append, batch}, stream) do
    Events.append(stream, Events.version(stream.id), batch)
  end

  defp attempt(:append_stale, stream) do
    Events.append(stream, Events.version(stream.id) + 1, [event()])
  end

  defp attempt(:append_invalid, stream) do
    Events.append(stream, Events.version(stream.id), [event(), %{type: "BAD"}])
  end

  defp attempt({:sql, sql}, _stream) do
    try do
      Repo.transaction(fn -> Repo.query!(sql) end)
    rescue
      Postgrex.Error -> :refused
    end
  end

  # Every stored event, keyed by position.
  defp snapshot do
    Events.read_all(0, 1_000_000) |> Map.new(&{&1.position, &1})
  end

  defp assert_refused(sql) do
    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn -> Repo.query!(sql) end)
      end

    assert error.postgres.message =~ "events is append-only"
  end

  defp uuid_bin(uuid \\ Ecto.UUID.generate(version: 7)) do
    {:ok, bin} = Ecto.UUID.dump(uuid)
    bin
  end
end
