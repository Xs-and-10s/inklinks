defmodule Inklinks.RatingTest do
  @moduledoc """
  Ratings after a finale, abandoned readings, resumptions and returns: what
  the log says about how a reading ended, or didn't.
  """
  use Inklinks.DataCase, async: true

  alias Inklinks.{Abandonment, Events, Inquest, Rating, Reading}

  @ex3 "ex3-the-fall-of-the-old-regime"
  @fixture "ex4-littlejon-thornbury"

  setup do
    %{reader: Ecto.UUID.generate(version: 7)}
  end

  describe "reaching a finale" do
    test "asks for a rating, with no path question when no fork was involved", %{reader: reader} do
      reading = to_the_end(reader, @ex3)

      assert reading.rating == :asking

      assert %{data: %{"ending" => "the_list", "path" => false}} =
               last_event(reading, "rating_asked")
    end

    test "after taking a fork, asks about the path too", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @fixture)
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")
      {:ok, reading} = Inquest.take(reading, "free_the_widow")
      reading = play_on(reading)

      assert %{data: %{"ending" => "ch4", "path" => true}} = last_event(reading, "rating_asked")
    end

    test "after declining a fork, asks about the path too", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @fixture)
      {:ok, reading} = Inquest.open(reading)
      {:ok, reading, :inquest_mode} = Inquest.answer(reading, nil)
      {:ok, reading, _} = Inquest.look(reading, "obey_at_thornbury")
      {:ok, reading} = Inquest.leave(reading)
      reading = play_on(reading)

      assert %{data: %{"path" => true}} = last_event(reading, "rating_asked")
    end
  end

  describe "answering the ratings box" do
    test "records the scores given, and only those", %{reader: reader} do
      reading = to_the_end(reader, @ex3)

      {:ok, reading} = Rating.answer(reading, %{"ending" => "5", "inklink" => 4, "path" => "3"})

      assert reading.rating == :done
      # No fork was involved, so a path score is not kept
      assert last_event(reading, "rating_given").data == %{
               "ending" => "the_list",
               "ending_score" => 5,
               "inklink_score" => 4
             }
    end

    test "with More…, records the moment they would change", %{reader: reader} do
      reading = to_the_end(reader, @ex3)
      [first | _] = Rating.moments(reading)
      assert first.chose == "“They named me Skittles.”"

      {:ok, reading} =
        Rating.answer(reading, %{
          "ending" => "4",
          "change_at" => "#{first.at}",
          "change_text" => " Keep the box. "
        })

      assert %{
               data: %{
                 "nib" => "arrival",
                 "chose" => "“They named me Skittles.”",
                 "text" => "Keep the box."
               }
             } =
               last_event(reading, "change_wished")
    end

    test "with nothing at all is the same as Not now", %{reader: reader} do
      reading = to_the_end(reader, @ex3)

      {:ok, reading} = Rating.answer(reading, %{"ending" => "", "inklink" => "nine"})

      assert reading.rating == :done
      assert last_event(reading, "rating_dismissed")
      refute last_event(reading, "rating_given")
    end

    test "is asked once per reading, and never again for an ending already rated", %{
      reader: reader
    } do
      reading = to_the_end(reader, @ex3)
      {:ok, _} = Rating.answer(reading, %{"ending" => "5"})
      assert {:error, :not_now} = Rating.answer(reading |> reload(), %{"ending" => "1"})

      # A second reading to the same ending is not asked
      again = to_the_end(reader, @ex3)
      assert again.rating == :none
      refute last_event(again, "rating_asked")
    end

    test "a dismissed rating does not stop the next reading asking", %{reader: reader} do
      reading = to_the_end(reader, @ex3)
      {:ok, _} = Rating.dismiss(reading)

      assert to_the_end(reader, @ex3).rating == :asking
    end
  end

  describe "starting again after finishing" do
    test "is recorded as a return, with the endings already seen", %{reader: reader} do
      first = to_the_end(reader, @ex3)

      assert first.id
             |> Events.read_stream()
             |> Enum.all?(&(&1.type != "returned_for_another_ending"))

      {:ok, again} = Reading.start(reader, @ex3)

      assert %{data: %{"readings_finished" => 1, "endings_seen" => ["the_list"]}} =
               last_event(again, "returned_for_another_ending")
    end
  end

  describe "re-reading a Nib" do
    test "counts the visit on nib_shown" do
      {:ok, reading} = Reading.start(Ecto.UUID.generate(version: 7), "the-well")
      {:ok, reading} = Reading.take(reading, "shoo_him_off")
      {:ok, reading} = Reading.take(reading, "back_to_the_well")

      assert %{data: %{"nib" => "well", "visit" => 2}} = last_event(reading, "nib_shown")
    end
  end

  describe "a reading left alone" do
    test "is inferred abandoned after a day, at the moment it stopped", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @ex3)
      {:ok, reading} = Reading.take(reading, "arrival#1")
      stopped = last_event(reading, "nib_shown").occurred_at

      # Other tests' committed rows may be swept too; only this reading matters.
      Abandonment.sweep(DateTime.add(stopped, 23 * 3600, :second))
      refute last_event(reading, "reading_abandoned")

      Abandonment.sweep(DateTime.add(stopped, 25 * 3600, :second))
      abandoned = last_event(reading, "reading_abandoned")
      assert abandoned.data["nib"] == "trial"
      assert abandoned.occurred_at == stopped

      # Not twice
      Abandonment.sweep(DateTime.add(stopped, 50 * 3600, :second))
      assert Enum.count(Events.read_stream(reading.id), &(&1.type == "reading_abandoned")) == 1
    end

    test "is never inferred abandoned once finished", %{reader: reader} do
      reading = to_the_end(reader, @ex3)
      Abandonment.sweep(DateTime.add(DateTime.utc_now(), 30 * 24 * 3600, :second))

      refute last_event(reading, "reading_abandoned")
    end

    test "that the Linker comes back to records a resumption first", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @ex3)
      Abandonment.sweep(DateTime.add(DateTime.utc_now(), 2 * 24 * 3600, :second))

      {:ok, reading} = Reading.load(reading.id, reader)
      assert reading.abandoned

      {:ok, reading} = Reading.take(reading, "arrival#2")

      assert [
               %{type: "reading_abandoned"},
               %{type: "reading_resumed", data: %{"nib" => "arrival"}},
               %{type: "link_taken"} | _
             ] =
               reading.id
               |> Events.read_stream()
               |> Enum.drop_while(&(&1.type != "reading_abandoned"))

      refute reading.abandoned
    end
  end

  # -- helpers -----------------------------------------------------------------

  defp to_the_end(reader, inklink) do
    {:ok, reading} = Reading.start(reader, inklink)
    play_on(reading)
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

  defp reload(reading) do
    {:ok, reading} = Reading.load(reading.id, reading.reader_id)
    reading
  end

  defp last_event(reading, type) do
    reading.id |> Events.read_stream() |> Enum.filter(&(&1.type == type)) |> List.last()
  end
end
