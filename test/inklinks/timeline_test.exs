defmodule Inklinks.TimelineTest do
  @moduledoc """
  A reading's path on the Littlejon fixture. ch2 offers “Stay at Eyrad’s
  side” (hiding “Free her, unseen”, askable from ch3, and “Speak in Sister
  Agathe’s ear”) and “Make yourself watch” (hiding nothing). ch3 offers
  “Promise her you will burn it”, hiding “Burn it”.
  """
  use Inklinks.DataCase, async: true
  use ExUnitProperties

  alias Inklinks.{Events, Inquest, Reading, Steps, Timeline}

  @fixture "ex4-littlejon-thornbury"

  setup do
    {:ok, reading} = Reading.start(Ecto.UUID.generate(version: 7), @fixture)
    %{reading: reading}
  end

  describe "a Linker who has only just begun" do
    test "is one row, where they are, with nothing yet not taken", %{reading: reading} do
      %Timeline{rows: [row], lanes: 1, done: false} = Timeline.build(reading)

      assert %{nib: "ch2", lane: 0, live: true, here: true, via: nil, not_taken: []} = row
      assert row.excerpt != ""
      assert String.length(row.excerpt) <= 91
    end
  end

  describe "a Linker who read straight through" do
    setup %{reading: reading} do
      {:ok, reading} = Reading.take(reading, "watch_what_unfolds")
      {:ok, reading} = Reading.take(reading, "keep_the_book")
      %{timeline: Timeline.build(reading)}
    end

    test "is one lane, every choice an offered Link", %{timeline: t} do
      assert t.lanes == 1
      assert Enum.map(t.rows, & &1.lane) |> Enum.uniq() == [0]

      assert [nil, %{kind: :link, label: "Make yourself watch"}, %{kind: :link} | _] =
               Enum.map(t.rows, & &1.via)
    end

    test "shows what was offered and not taken, and no fork", %{timeline: t} do
      [ch2 | _] = t.rows
      assert ch2.not_taken == [%{kind: :link, label: "Stay at Eyrad’s side"}]
      refute t |> inspect() |> String.contains?("Free her")
    end
  end

  describe "a Linker who freed the widow at ch2, after looking at both forks" do
    setup %{reading: reading} do
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")
      {:ok, reading} = Inquest.take(reading, "free_the_widow")
      %{timeline: Timeline.build(reading)}
    end

    test "the fork stands in the path, in place of the Link it replaced", %{timeline: t} do
      [ch2, alt] = t.rows

      assert alt.via == %{
               kind: :fork,
               label: "Free her, unseen",
               instead: "Stay at Eyrad’s side",
               back: false
             }

      assert alt.lane == 0 and t.lanes == 1

      # The other offered Link, then the fork looked at and left
      assert ch2.not_taken == [
               %{kind: :link, label: "Make yourself watch"},
               %{kind: :fork, label: "Speak in Sister Agathe’s ear"}
             ]
    end
  end

  describe "a Linker who went back from ch3 to free the widow" do
    setup %{reading: reading} do
      {:ok, reading} = Reading.take(reading, "watch_what_unfolds")
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, "I should have saved her")
      [_, %{at: at} | _] = Reading.places(reading)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury", at)
      {:ok, reading} = Inquest.take(reading, "free_the_widow")
      %{timeline: Timeline.build(reading)}
    end

    test "branches at ch2: the path left in lane 1, the live one straight down", %{timeline: t} do
      assert [{"ch2", 0, true}, {"ch3", 1, false}, {"ch2_alt", 0, true}] =
               Enum.map(t.rows, &{&1.nib, &1.lane, &1.live})

      assert t.lanes == 2
      [ch2, ch3, alt] = t.rows
      assert ch3.went_back and not ch2.went_back
      assert alt.parent == ch2.version
      assert alt.via.back and alt.via.kind == :fork
    end

    test "draws the live edge through the row of the path left", %{timeline: t} do
      [ch2, ch3, alt] = t.rows
      assert %{seg: :elbow, lane: 1, from: 0, kind: :link, live: false} in ch2.lines
      assert %{seg: :bottom, lane: 0, from: 0, kind: :fork, live: true} in ch2.lines
      assert %{seg: :through, lane: 0, from: 0, kind: :fork, live: true} in ch3.lines
      assert %{seg: :top, lane: 1, from: 0, kind: :link, live: false} in ch3.lines
      assert [%{seg: :top, lane: 0}] = alt.lines
    end

    test "never names the fork asked for from ch3 that was not offered there", %{timeline: t} do
      refute t |> inspect() |> String.contains?("Speak in")
    end
  end

  # -- the invariants -----------------------------------------------------------

  property "a timeline is a tree drawn narrow, and names only forks the Linker saw" do
    check all(steps <- list_of(Steps.step(), max_length: 40), max_runs: 50) do
      {:ok, start} = Reading.start(Ecto.UUID.generate(version: 7), @fixture)
      reading = Enum.reduce(steps, start, &Steps.run/2)
      {:ok, reading} = Reading.load(reading.id, reading.reader_id)

      t = Timeline.build(reading)
      events = Events.read_stream(reading.id)

      # One row per Nib shown, in order
      assert Enum.map(t.rows, & &1.version) ==
               for(%{type: "nib_shown", stream_version: v} <- events, do: v)

      # A tree: every parent is an earlier row
      for {row, i} <- Enum.with_index(t.rows), row.parent do
        assert Enum.find_index(t.rows, &(&1.version == row.parent)) < i
      end

      # The live path is lane 0 and ends at the last row; nothing else is lane 0
      assert Enum.all?(t.rows, &(&1.live == (&1.lane == 0)))
      assert List.last(t.rows).live

      # At most one lane per time the Linker went back
      went_back =
        Enum.count(
          events,
          &match?(%{type: "fork_taken", data: %{"back_to" => b}} when b != nil, &1)
        )

      assert t.lanes <= went_back + 1

      # Every fork named was shown to the Linker
      seen = MapSet.new(for %{type: "fork_looked", data: %{"label" => l}} <- events, do: l)

      named =
        for row <- t.rows,
            item <- [row.via | row.not_taken],
            match?(%{kind: :fork}, item),
            do: item.label

      assert MapSet.subset?(MapSet.new(named), seen)
    end
  end
end
