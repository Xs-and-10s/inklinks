defmodule Inklinks.InquestTest do
  @moduledoc """
  Flow D on the Littlejon fixture: ch2 hides one fork (`free_the_widow`,
  standing in for `obey_at_thornbury`) beside a canon Link with none
  (`shut_your_eyes`). ch2_alt and ch3 hide nothing.
  """
  use Inklinks.DataCase, async: true
  use ExUnitProperties

  alias Inklinks.{Events, Inquest, Reading}

  @fixture "ex4-littlejon-thornbury"

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
      reading = forked(reading)
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

  describe "an Inquest where the Inker hid a fork" do
    test "skipping the box still enters Inquest mode", %{reading: reading} do
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)

      assert reading.inquest == :mode
      assert [%{type: "inquest_skipped"}, %{type: "inquest_mode_entered"}] = recent(reading, 2)
    end

    test "looking flips the canon Link to its fork, and is free", %{reading: reading} do
      reading = in_mode(reading)

      {:ok, reading, {:fork, fork}} = Inquest.look(reading, "obey_at_thornbury")
      {:ok, reading, {:fork, ^fork}} = Inquest.look(reading, "obey_at_thornbury")

      assert fork == %{id: "free_the_widow", label: ["Free her, unseen"]}
      assert Reading.remaining(reading) == 3
      # The first look is recorded; looking again is not.
      assert reading.id |> Events.read_stream() |> Enum.count(&(&1.type == "fork_looked")) == 1
    end

    test "taking a fork that was looked at spends one Inquest and goes down it", %{
      reading: reading
    } do
      reading = in_mode(reading)
      {:ok, reading, {:fork, _}} = Inquest.look(reading, "obey_at_thornbury")

      {:ok, reading} = Inquest.take(reading, "free_the_widow")

      assert Reading.remaining(reading) == 2
      assert Reading.view(reading).nib == "ch2_alt"
      assert reading.inquest == :none

      assert [
               %{
                 type: "fork_taken",
                 data: %{"fork" => "free_the_widow", "canon" => "obey_at_thornbury"}
               },
               %{type: "nib_shown"}
             ] =
               recent(reading, 2)
    end

    test "a fork never looked at cannot be taken", %{reading: reading} do
      reading = in_mode(reading)

      assert {:error, :not_offered} = Inquest.take(reading, "free_the_widow")
      assert Reading.remaining(reading) == 3
    end

    test "a canon Link with no fork asks what they wanted, then hands the choice back", %{
      reading: reading
    } do
      reading = in_mode(reading)

      {:ok, reading, :asked} = Inquest.want(reading, "shut_your_eyes")
      {:ok, reading} = Inquest.answer_wanted(reading, "Ixë should look.")

      # Never followed for them: still at ch2, out of Inquest mode
      assert Reading.view(reading).nib == "ch2"
      assert reading.inquest == :none

      assert [
               %{type: "wanted_instead_opened", data: %{"canon" => "shut_your_eyes"}},
               %{type: "wanted_instead_submitted", data: %{"text" => "Ixë should look."}},
               %{type: "inquest_mode_left", data: %{"reason" => "wanted_instead"}}
             ] = recent(reading, 3)
    end

    test "a canon Link that has a fork flips instead of asking", %{reading: reading} do
      assert {:ok, reading, {:fork, %{id: "free_the_widow"}}} =
               reading |> in_mode() |> Inquest.want("obey_at_thornbury")

      assert reading.inquest == :mode
    end

    test "leaving after looking declines the fork", %{reading: reading} do
      reading = in_mode(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")

      {:ok, reading} = Inquest.leave(reading)

      assert [
               %{type: "fork_declined", data: %{"fork" => "free_the_widow", "by" => "left"}},
               %{type: "inquest_mode_left", data: %{"reason" => "left"}}
             ] = recent(reading, 2)
    end

    test "with no Inquests left is noted, and Inquest mode never opens", %{reading: reading} do
      reading = %{reading | spent: 3}

      {:ok, reading} = Inquest.open(reading)
      {:ok, _reading, :noted} = Inquest.answer(reading, "I want her saved.")
    end
  end

  describe "a reading with Inquests, rebuilt from its log" do
    test "is in the same place in flow D", %{reading: reading} do
      reading = in_mode(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")

      {:ok, rebuilt} = Reading.load(reading.id, reading.reader_id)

      assert rebuilt.inquest == :mode
      assert rebuilt.looked == %{"free_the_widow" => "obey_at_thornbury"}
      assert {:ok, _} = Inquest.take(rebuilt, "free_the_widow")
    end
  end

  # -- the invariant -----------------------------------------------------------

  property "an Inquest is spent exactly when a fork is taken" do
    check all(steps <- list_of(step(), max_length: 30), max_runs: 40) do
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

      # …no fork ever appears among the Links a Nib shows…
      for %{type: "nib_shown", data: %{"links" => links}} <- events do
        refute "free_the_widow" in links
      end

      # …and the log rebuilds the same reading.
      {:ok, rebuilt} = Reading.load(final.id, final.reader_id)

      assert {rebuilt.spent, rebuilt.inquest, rebuilt.looked} ==
               {final.spent, final.inquest, final.looked}

      assert Reading.view(rebuilt) == Reading.view(final)
    end
  end

  # Everything a Linker (or a forged request) might try, in any order.
  defp step do
    one_of([
      constant(:open),
      tuple({constant(:answer), one_of([constant(nil), string(:printable, max_length: 30)])}),
      tuple({constant(:look), link_id()}),
      tuple({constant(:take_fork), link_id()}),
      tuple({constant(:want), link_id()}),
      tuple({constant(:answer_wanted), one_of([constant(nil), constant("instead")])}),
      constant(:leave),
      tuple({constant(:take), link_id()})
    ])
  end

  defp link_id do
    member_of(~w(obey_at_thornbury free_the_widow shut_your_eyes on_to_the_fens nonsense))
  end

  defp run(:open, r), do: ok(Inquest.open(r), r)
  defp run({:answer, text}, r), do: ok(Inquest.answer(r, text), r)
  defp run({:look, id}, r), do: ok(Inquest.look(r, id), r)
  defp run({:take_fork, id}, r), do: ok(Inquest.take(r, id), r)
  defp run({:want, id}, r), do: ok(Inquest.want(r, id), r)
  defp run({:answer_wanted, text}, r), do: ok(Inquest.answer_wanted(r, text), r)
  defp run(:leave, r), do: ok(Inquest.leave(r), r)
  defp run({:take, id}, r), do: ok(Reading.take(r, id), r)

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

  defp forked(reading) do
    reading = in_mode(reading)
    {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")
    {:ok, reading} = Inquest.take(reading, "free_the_widow")
    reading
  end

  defp recent(reading, n), do: reading.id |> Events.read_stream() |> Enum.take(-n)
end
