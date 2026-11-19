defmodule Inklinks.InquestTest do
  @moduledoc """
  Flow D on the Littlejon fixture. ch2's offered Link `obey_at_thornbury`
  hides two forks, in this order: `free_the_widow` (which may also be asked
  for from ch3) and `speak_in_her_ear`. Its other offered Link,
  `watch_what_unfolds`, hides none. ch3's `keep_the_book` hides
  `burn_the_book`. ch2_alt, ch2_voice and ch3_alt hide nothing.
  """
  use Inklinks.DataCase, async: true
  use ExUnitProperties

  alias Inklinks.{Events, Inquest, Reading}

  @fixture "ex4-littlejon-thornbury"
  @free %{id: "free_the_widow", label: ["Free her, unseen"]}
  @speak %{id: "speak_in_her_ear", label: ["Speak in Sister Agathe’s ear"]}

  setup do
    {:ok, reading} = Reading.start(Ecto.UUID.generate(version: 7), @fixture)
    %{reading: reading}
  end

  describe "an Inklink whose Inker declared Inquests" do
    test "gives each reading the budget, and none to a story without forks", %{reading: reading} do
      assert reading.budget == 3
      assert Reading.remaining(reading) == 3

      {:ok, ex3} = Reading.start(reading.reader_id, "ex3-the-fall-of-the-old-regime")
      assert ex3.budget == 0
      assert {:error, :not_now} = Inquest.open(ex3)
    end
  end

  describe "an Inquest where the Inker hid nothing" do
    test "is noted, turned down and costs nothing", %{reading: reading} do
      # Given a Linker at ch2_alt, where no fork is hidden
      reading = forked(reading, @free.id)
      remaining = Reading.remaining(reading)

      # When they ask, and say what they'd change
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, outcome} = Inquest.answer(reading, "  Let Eyrad argue back.  ")

      # Then it is noted, nothing is spent, and they carry on
      assert outcome == :noted
      assert Reading.remaining(reading) == remaining
      assert reading.inquest == :none

      assert [
               %{type: "inquest_opened"},
               %{type: "inquest_submitted", data: %{"text" => "Let Eyrad argue back."}},
               %{type: "inquest_turned_down", data: %{"reason" => "no_forks"}}
             ] = recent(reading, 3)
    end
  end

  describe "an Inquest where the Inker hid forks" do
    test "skipping the box still enters Inquest mode", %{reading: reading} do
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)

      assert reading.inquest == :mode
      assert [%{type: "inquest_skipped"}, %{type: "inquest_mode_entered"}] = recent(reading, 2)
    end

    test "looking opens the offered Link into all its forks, in the Inker's order, for free",
         %{reading: reading} do
      reading = in_mode(reading)

      {:ok, reading, {:forks, forks}} = Inquest.look(reading, "obey_at_thornbury")
      {:ok, reading, {:forks, ^forks}} = Inquest.look(reading, "obey_at_thornbury")

      assert forks == [@free, @speak]
      assert Reading.remaining(reading) == 3

      # Each fork shown is recorded once; looking again is not.
      looked =
        reading.id
        |> Events.read_stream()
        |> Enum.filter(&(&1.type == "fork_looked"))
        |> Enum.map(& &1.data["fork"])

      assert looked == [@free.id, @speak.id]
    end

    test "taking one fork spends one Inquest, goes down it, and declines the others",
         %{reading: reading} do
      reading = in_mode(reading)
      {:ok, reading, {:forks, _}} = Inquest.look(reading, "obey_at_thornbury")

      {:ok, reading} = Inquest.take(reading, @speak.id)

      assert Reading.remaining(reading) == 2
      assert Reading.view(reading).nib == "ch2_voice"
      assert reading.inquest == :none

      assert [
               %{
                 type: "fork_taken",
                 data: %{"fork" => "speak_in_her_ear", "link" => "obey_at_thornbury"}
               },
               %{
                 type: "fork_declined",
                 data: %{"fork" => "free_the_widow", "by" => "took_another_fork"}
               },
               %{type: "nib_shown"}
             ] = recent(reading, 3)
    end

    test "a fork never looked at cannot be taken", %{reading: reading} do
      reading = in_mode(reading)

      assert {:error, :not_offered} = Inquest.take(reading, @free.id)
      assert Reading.remaining(reading) == 3
    end

    test "an offered Link with no fork asks what they wanted, then hands the choice back",
         %{reading: reading} do
      reading = in_mode(reading)

      {:ok, reading, :asked} = Inquest.want(reading, "watch_what_unfolds")
      {:ok, reading} = Inquest.answer_wanted(reading, "Ixë should look away.")

      # Never followed for them: still at ch2, out of Inquest mode
      assert Reading.view(reading).nib == "ch2"
      assert reading.inquest == :none

      assert [
               %{type: "wanted_instead_opened", data: %{"link" => "watch_what_unfolds"}},
               %{type: "wanted_instead_submitted", data: %{"text" => "Ixë should look away."}},
               %{type: "inquest_mode_left", data: %{"reason" => "wanted_instead"}}
             ] = recent(reading, 3)
    end

    test "an offered Link with forks opens instead of asking", %{reading: reading} do
      assert {:ok, reading, {:forks, [@free, @speak]}} =
               reading |> in_mode() |> Inquest.want("obey_at_thornbury")

      assert reading.inquest == :mode
    end

    test "leaving after looking declines every fork looked at", %{reading: reading} do
      reading = in_mode(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")

      {:ok, reading} = Inquest.leave(reading)

      assert [
               %{type: "fork_declined", data: %{"fork" => "free_the_widow", "by" => "left"}},
               %{type: "fork_declined", data: %{"fork" => "speak_in_her_ear", "by" => "left"}},
               %{type: "inquest_mode_left", data: %{"reason" => "left"}}
             ] = recent(reading, 3)
    end

    test "with no Inquests left is noted, and Inquest mode never opens", %{reading: reading} do
      reading = %{reading | spent: 3}

      {:ok, reading} = Inquest.open(reading)
      {:ok, _reading, :noted} = Inquest.answer(reading, "I want her saved.")
    end
  end

  describe "a fork asked for from a later Nib" do
    setup %{reading: reading} do
      # Given a Linker who obeyed at ch2 and is now at ch3, in Inquest mode
      {:ok, reading} = Reading.take(reading, "obey_at_thornbury")
      %{reading: in_mode(reading)}
    end

    test "is offered beside ch3's own, under the choice it would undo", %{reading: reading} do
      assert [%{nib: "ch3", at: nil}, %{nib: "ch2", at: at, chose: "Stay at Eyrad’s side"}] =
               Reading.places(reading)

      assert {:ok, reading, {:forks, [%{id: "burn_the_book"}]}} =
               Inquest.look(reading, "keep_the_book")

      # Only the fork marked `from ch3`: speak_in_her_ear is asked for at ch2 alone
      assert {:ok, reading, {:forks, [@free]}} = Inquest.look(reading, "obey_at_thornbury", at)
      assert {:ok, _, :no_forks} = Inquest.look(reading, "watch_what_unfolds", at)
    end

    test "goes back to that visit, takes the fork, and keeps the Inquests spent", %{
      reading: reading
    } do
      [_, %{at: at}] = Reading.places(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury", at)

      {:ok, reading} = Inquest.take(reading, @free.id)

      assert Reading.view(reading).nib == "ch2_alt"
      assert Reading.remaining(reading) == 2

      assert [
               %{
                 type: "fork_taken",
                 data: %{
                   "nib" => "ch3",
                   "at" => "ch2",
                   "back_to" => ^at,
                   "link" => "obey_at_thornbury"
                 }
               },
               %{type: "nib_shown", data: %{"nib" => "ch2_alt"}}
             ] = recent(reading, 2)

      # The world went back too: at ch3 again, the widow lives
      {:ok, reading} = Reading.take(reading, "on_to_the_fens")
      refute inspect(Reading.view(reading).ink) =~ "the third time she did not come up singing"
    end

    test "a reading that went back rebuilds from its log to the same place", %{reading: reading} do
      [_, %{at: at}] = Reading.places(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury", at)
      {:ok, reading} = Inquest.take(reading, @free.id)

      {:ok, rebuilt} = Reading.load(reading.id, reading.reader_id)

      assert Reading.view(rebuilt) == Reading.view(reading)
      assert rebuilt.spent == 1
    end
  end

  describe "a reading with Inquests, rebuilt from its log" do
    test "is in the same place in flow D", %{reading: reading} do
      reading = in_mode(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")

      {:ok, rebuilt} = Reading.load(reading.id, reading.reader_id)

      assert rebuilt.inquest == :mode
      assert rebuilt.looked |> Map.keys() |> Enum.sort() == [@free.id, @speak.id]
      assert {:ok, _} = Inquest.take(rebuilt, @free.id)
    end
  end

  # -- the invariant -----------------------------------------------------------

  property "an Inquest is spent exactly when a fork is taken" do
    check all(steps <- list_of(step(), max_length: 40), max_runs: 50) do
      {:ok, start} = Reading.start(Ecto.UUID.generate(version: 7), @fixture)

      final =
        Enum.reduce(steps, start, fn step, reading ->
          before_remaining = Reading.remaining(reading)
          before_taken = forks_taken(reading)

          reading = run(step, reading)

          taken_now = forks_taken(reading) - before_taken
          # Remaining falls by exactly the forks taken in this step, never below 0
          assert Reading.remaining(reading) == before_remaining - taken_now
          assert taken_now in [0, 1]
          assert Reading.remaining(reading) >= 0
          reading
        end)

      events = Events.read_stream(final.id)

      # The budget, less every fork_taken, is what is left…
      assert Reading.remaining(final) ==
               final.budget - Enum.count(events, &(&1.type == "fork_taken"))

      # …every fork taken had been looked at in the same Inquest mode…
      for {%{type: "fork_taken", data: %{"fork" => f}}, i} <- Enum.with_index(events) do
        since_nib =
          events |> Enum.take(i) |> Enum.reverse() |> Enum.take_while(&(&1.type != "nib_shown"))

        assert Enum.any?(since_nib, &match?(%{type: "fork_looked", data: %{"fork" => ^f}}, &1))
      end

      # …no fork ever appears among the Links a Nib offers…
      forks = MapSet.new(~w(free_the_widow speak_in_her_ear burn_the_book))

      for %{type: "nib_shown", data: %{"links" => links}} <- events do
        assert MapSet.disjoint?(MapSet.new(links), forks)
      end

      # …and the log rebuilds the same reading.
      {:ok, rebuilt} = Reading.load(final.id, final.reader_id)

      assert {rebuilt.spent, rebuilt.inquest, rebuilt.looked} ==
               {final.spent, final.inquest, final.looked}

      assert Reading.view(rebuilt) == Reading.view(final)
    end
  end

  # Everything a Linker (or a forged request) might try, in any order: at
  # the current Nib, or at an earlier one (the first earlier place, if any).
  defp step do
    one_of([
      constant(:open),
      tuple({constant(:answer), one_of([constant(nil), string(:printable, max_length: 30)])}),
      tuple({constant(:look), link_id(), boolean()}),
      tuple({constant(:take_fork), link_id()}),
      tuple({constant(:want), link_id(), boolean()}),
      tuple({constant(:answer_wanted), one_of([constant(nil), constant("instead")])}),
      constant(:leave),
      tuple({constant(:take), link_id()})
    ])
  end

  defp link_id do
    member_of(
      ~w(obey_at_thornbury watch_what_unfolds free_the_widow speak_in_her_ear keep_the_book
                 burn_the_book on_to_the_fens south_to_the_fens on_to_halde nonsense)
    )
  end

  defp run(:open, r), do: ok(Inquest.open(r), r)
  defp run({:answer, text}, r), do: ok(Inquest.answer(r, text), r)
  defp run({:look, id, earlier?}, r), do: ok(Inquest.look(r, id, at(r, earlier?)), r)
  defp run({:take_fork, id}, r), do: ok(Inquest.take(r, id), r)
  defp run({:want, id, earlier?}, r), do: ok(Inquest.want(r, id, at(r, earlier?)), r)
  defp run({:answer_wanted, text}, r), do: ok(Inquest.answer_wanted(r, text), r)
  defp run(:leave, r), do: ok(Inquest.leave(r), r)
  defp run({:take, id}, r), do: ok(Reading.take(r, id), r)

  defp at(_r, false), do: nil

  defp at(r, true) do
    case Reading.places(r) do
      [_, %{at: at} | _] -> at
      _ -> nil
    end
  end

  defp ok({:ok, reading}, _), do: reading
  defp ok({:ok, reading, _}, _), do: reading
  defp ok({:error, _}, reading), do: reading

  defp forks_taken(reading),
    do: reading.id |> Events.read_stream() |> Enum.count(&(&1.type == "fork_taken"))

  # -- helpers -----------------------------------------------------------------

  defp in_mode(reading) do
    {:ok, reading} = Inquest.open(reading)
    {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)
    reading
  end

  defp forked(reading, fork) do
    reading = in_mode(reading)
    {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")
    {:ok, reading} = Inquest.take(reading, fork)
    reading
  end

  defp recent(reading, n), do: reading.id |> Events.read_stream() |> Enum.take(-n)
end
