defmodule Inklinks.InsightsTest do
  @moduledoc """
  The Inker's questions, answered from the log of real readings: if these
  pass, the events hold what an Inker needs.
  """
  use Inklinks.DataCase, async: true

  alias Inklinks.{Abandonment, Events, Inquest, Insights, Rating, Reading}

  @fixture "ex4-littlejon-thornbury"

  describe "on the Littlejon fixture" do
    setup do
      # One reader frees the widow, rates it, and comes back to read again
      a = Ecto.UUID.generate(version: 7)
      {:ok, r} = Reading.start(a, @fixture)
      {:ok, r} = Inquest.open(r)
      {:ok, r, :inquest_mode} = Inquest.answer(r, "Don't let her drown.")
      {:ok, r, _} = Inquest.look(r, "obey_at_thornbury")
      {:ok, r} = Inquest.take(r, "free_the_widow")
      r = play_on(r)
      {:ok, _} = Rating.answer(r, %{"ending" => "5", "inklink" => "4", "path" => "5"})
      {:ok, _} = Reading.start(a, @fixture)

      # Another looks, leaves, asks for something hidden nowhere, and stops at ch3
      b = Ecto.UUID.generate(version: 7)
      {:ok, r} = Reading.start(b, @fixture)
      {:ok, r} = Inquest.open(r)
      {:ok, r, :inquest_mode} = Inquest.answer(r, nil)
      {:ok, r, _} = Inquest.look(r, "obey_at_thornbury")
      {:ok, r, :asked} = Inquest.want(r, "watch_what_unfolds")
      {:ok, r} = Inquest.answer_wanted(r, "Let him look away.")
      {:ok, r} = Reading.take(r, "watch_what_unfolds")
      {:ok, r} = Inquest.open(r)
      {:ok, _r, :inquest_mode} = Inquest.answer(r, "Make Maud kinder.")

      Abandonment.sweep(DateTime.add(DateTime.utc_now(), 2 * 24 * 3600, :second))
      :ok
    end

    test "where readers stop" do
      # The second reader, and the first reader's new reading, never finished
      assert [%{nib: "ch2", readings: 1}, %{nib: "ch3", readings: 1}] = Insights.stops(@fixture)
    end

    test "what happened to each fork" do
      forks = Map.new(Insights.forks(@fixture), &{&1.fork, &1})

      # The first reader took the widow's fork (declining the other);
      # the second looked at both and declined both.
      assert %{looked: 2, taken: 1, declined: 1} = forks["free_the_widow"]
      assert %{looked: 2, taken: 0, declined: 2} = forks["speak_in_her_ear"]
    end

    test "what readers asked for, in their words" do
      assert [
               %{
                 kind: "inquest_submitted",
                 nib: "ch2",
                 text: "Don't let her drown.",
                 outcome: "inquest_mode"
               },
               %{kind: "wanted_instead_submitted", nib: "ch2", text: "Let him look away."},
               %{
                 kind: "inquest_submitted",
                 nib: "ch3",
                 text: "Make Maud kinder.",
                 outcome: "inquest_mode"
               }
             ] = Insights.requests(@fixture)
    end

    test "ratings by ending" do
      assert [
               %{
                 ending: "ch4",
                 ratings: 1,
                 ending_score: 5.0,
                 inklink_score: 4.0,
                 path_score: 5.0
               }
             ] =
               Insights.ratings(@fixture)
    end

    test "returns" do
      assert %{returns: 1} = Insights.returns(@fixture)
      assert %{readers: 1} = Insights.rereads(@fixture)
    end
  end

  describe "time per Nib" do
    test "is the median from a Nib being shown to the Linker's next action" do
      t0 = ~U[2026-11-19 12:00:00.000000Z]

      for {seconds, id} <- [{30, 1}, {90, 2}, {60, 3}] do
        stream = %{
          type: "reading",
          id: Ecto.UUID.generate(version: 7),
          reader_id: Ecto.UUID.generate(version: 7),
          inklink_id: "timing"
        }

        {:ok, _} =
          Events.append(stream, 0, [
            %{type: "nib_shown", data: %{"nib" => "a", "visit" => 1}, occurred_at: t0},
            # written in the same moment: not the Linker's time
            %{type: "rating_asked", data: %{}, occurred_at: t0},
            %{
              type: "link_taken",
              data: %{"link" => "a#1"},
              occurred_at: DateTime.add(t0, seconds, :second)
            },
            %{
              type: "nib_shown",
              data: %{"nib" => "b", "visit" => 1},
              occurred_at: DateTime.add(t0, seconds, :second)
            }
          ])

        assert id in 1..3
      end

      # "b" was never left, so it has no time yet
      assert [%{nib: "a", median_seconds: 60.0, showings: 3}] = Insights.time_per_nib("timing")
    end
  end

  defp play_on(reading) do
    case Reading.view(reading) do
      %{done: true} ->
        reading

      %{links: [first | _]} ->
        {:ok, reading} = Reading.take(reading, first.id)
        play_on(reading)
    end
  end
end
