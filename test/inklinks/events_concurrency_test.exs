defmodule Inklinks.EventsConcurrencyTest do
  @moduledoc """
  Writers racing for the same stream version, on real connections.

  The SQL sandbox shares one connection per test, which serializes every
  transaction, so a race cannot happen inside it. This test runs outside the
  sandbox. Its rows stay in the test database: the log refuses deletes, and
  each run uses fresh stream ids.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Inklinks.Events
  alias Inklinks.Repo

  @writers 8

  test "when several writers expect the same version, exactly one wins" do
    Sandbox.unboxed_run(Repo, fn ->
      # Given a new reading
      stream = %{
        type: "reading",
        id: Ecto.UUID.generate(version: 7),
        reader_id: Ecto.UUID.generate(version: 7),
        inklink_id: "race"
      }

      # When eight writers each append one event, all expecting version 0
      results =
        1..@writers
        |> Task.async_stream(
          fn n ->
            Sandbox.unboxed_run(Repo, fn ->
              Events.append(stream, 0, [%{type: "racer", data: %{"n" => n}}])
            end)
          end,
          max_concurrency: @writers,
          timeout: 10_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      # Then one succeeds, the rest are told the stream is at version 1,
      # and the stream holds exactly one event
      assert Enum.count(results, &match?({:ok, [_]}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, {:wrong_expected_version, 1}})) == @writers - 1
      assert Events.version(stream.id) == 1
    end)
  end
end
