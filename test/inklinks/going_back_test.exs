defmodule Inklinks.GoingBackTest do
  @moduledoc """
  Which earlier visits a Linker may go back to, on "The Well", a test-only
  fixture: a hub visited each season, with a fork (`ask_his_name`) behind
  "Shoo him off" that may be asked for from the Harvest Fair, but only in
  the first two seasons.
  """
  use Inklinks.DataCase, async: true

  alias Inklinks.{Inquest, Reading}

  @well "the-well"

  describe "a Linker at the Fair who chose differently each season" do
    test "may go back to each season where the fork can be taken, newest first, with its cost" do
      # Shoo (spring), offer (summer), shoo (autumn: the fork is gone by then)
      reading = play(["shoo_him_off", "leave_an_offering", "shoo_him_off"])

      assert [
               %{nib: "fair", at: nil},
               %{nib: "well", chose: "Leave an offering", back: 4},
               %{nib: "well", chose: "Shoo him off", back: 6}
             ] = Reading.places(reading)
    end
  end

  describe "a Linker who made the same choice twice" do
    test "is offered it once, at the latest visit: going further back costs more for nothing" do
      # Shoo (spring), shoo (summer), offer (autumn)
      reading = play(["shoo_him_off", "shoo_him_off", "leave_an_offering"])

      assert [%{nib: "fair"}, %{nib: "well", chose: "Shoo him off", back: 4}] =
               Reading.places(reading)
    end
  end

  describe "going back to the visit the Linker picks" do
    test "undoes everything since it, and spends one Inquest" do
      reading = play(["shoo_him_off", "leave_an_offering", "shoo_him_off"])
      [_, _, %{at: spring}] = Reading.places(reading)

      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, "Be kind to him the first time.")

      {:ok, reading, {:forks, [%{id: "ask_his_name"}]}} =
        Inquest.look(reading, "shoo_him_off", spring)

      {:ok, reading} = Inquest.take(reading, "ask_his_name")

      # Back in spring's aftermath: the season turned once, not three times
      assert Reading.view(reading).nib == "season_turns"
      assert Enum.map(Reading.view(reading).links, & &1.id) == ["back_to_the_well"]
      assert Reading.remaining(reading) == 2
    end

    test "cannot reach a visit that was collapsed or filtered out" do
      reading = play(["shoo_him_off", "shoo_him_off", "leave_an_offering"])
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)

      # The spring visit (version 2) was collapsed into summer's
      assert {:error, :not_offered} = Inquest.look(reading, "shoo_him_off", 2)
    end
  end

  # Three seasons at the well, choosing as given, then on to the Fair.
  defp play(choices) do
    {:ok, reading} = Reading.start(Ecto.UUID.generate(version: 7), @well)

    reading =
      Enum.reduce(choices, reading, fn choice, reading ->
        {:ok, reading} = Reading.take(reading, choice)

        next =
          if Reading.view(reading).links |> Enum.any?(&(&1.id == "to_the_fair")),
            do: "to_the_fair",
            else: "back_to_the_well"

        {:ok, reading} = Reading.take(reading, next)
        reading
      end)

    assert Reading.view(reading).nib == "fair"
    reading
  end
end
