defmodule Inklinks.ReadingTest do
  @moduledoc """
  A reading as its event log sees it: what each step records, what is
  refused, and that the log alone is enough to rebuild where a Linker is.
  """
  use Inklinks.DataCase, async: true
  use ExUnitProperties

  alias Inklinks.{Events, Reading}

  @ex3 "ex3-the-fall-of-the-old-regime"

  setup do
    %{reader: Ecto.UUID.generate(version: 7)}
  end

  describe "starting a reading" do
    test "records the seed and the IR it started on, then the first Nib", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @ex3, seed: 42)

      [started, shown] = Events.read_stream(reading.id)

      assert started.type == "reading_started"
      assert %{"seed" => 42, "ir" => "2", "inquests" => 0} = started.data
      assert started.data["ir_sha256"] =~ ~r/^[0-9a-f]{64}$/
      assert started.reader_id == reader
      assert started.inklink_id == @ex3

      assert shown.type == "nib_shown"

      assert shown.data == %{
               "nib" => "arrival",
               "passed" => [],
               "links" => ~w(arrival#1 arrival#2 arrival#3),
               "visit" => 1
             }
    end

    test "refuses an Inklink the engine cannot play", %{reader: reader} do
      assert {:error, {:unsupported, reasons}} = Reading.start(reader, "ex1-the-night-train")
      assert "cohort mode" in reasons
    end
  end

  describe "taking a Link" do
    test "records the Link, where it was taken, and the Nib it led to", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @ex3)
      {:ok, reading} = Reading.take(reading, "arrival#1")

      [_, _, taken, shown] = Events.read_stream(reading.id)

      assert taken.type == "link_taken"

      assert taken.data == %{
               "link" => "arrival#1",
               "nib" => "arrival",
               "label" => "“They named me Skittles.”"
             }

      assert shown.data["nib"] == "trial"
      assert shown.data["passed"] == ["arrival:name"]
      assert reading.version == 4
    end

    test "that the Nib does not offer is refused, and nothing is recorded", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @ex3)

      assert {:error, :not_offered} = Reading.take(reading, "trial#1")
      assert {:error, :not_offered} = Reading.take(reading, "no such link")
      assert Events.version(reading.id) == 2
    end

    test "from a stale tab is refused, and nothing is recorded", %{reader: reader} do
      {:ok, tab_a} = Reading.start(reader, @ex3)
      tab_b = tab_a

      {:ok, _} = Reading.take(tab_a, "arrival#1")

      assert {:error, {:wrong_expected_version, 4}} = Reading.take(tab_b, "arrival#2")
      assert [_, _, %{data: %{"link" => "arrival#1"}}, _] = Events.read_stream(tab_a.id)
    end
  end

  describe "reaching the end" do
    test "records the ending, finishes the reading, and stops it being current", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @ex3)
      assert Reading.current(reader, @ex3) == reading.id

      reading = play_to_end(reading)

      types = reading.id |> Events.read_stream() |> Enum.map(& &1.type)
      assert Enum.take(types, -4) == ~w(nib_shown ending_reached rating_asked reading_finished)
      assert List.last(Events.read_stream(reading.id)).data == %{"ending" => "the_list"}
      assert Reading.current(reader, @ex3) == nil
    end
  end

  describe "a reading" do
    test "belongs to its reader alone", %{reader: reader} do
      {:ok, reading} = Reading.start(reader, @ex3)

      assert {:ok, _} = Reading.load(reading.id, reader)
      assert {:error, :not_found} = Reading.load(reading.id, Ecto.UUID.generate(version: 7))
      assert {:error, :not_found} = Reading.load("not-a-uuid", reader)
    end

    property "rebuilt from its log is exactly where the Linker left it, and every recorded Link was on offer" do
      check all(
              seed <- positive_integer(),
              choices <-
                list_of(one_of([non_negative_integer(), string(:alphanumeric)]), max_length: 14),
              max_runs: 30
            ) do
        reader = Ecto.UUID.generate(version: 7)
        {:ok, reading} = Reading.start(reader, @ex3, seed: seed)

        live = Enum.reduce(choices, reading, &try_link/2)

        {:ok, rebuilt} = Reading.load(reading.id, reader)
        assert Reading.view(rebuilt) == Reading.view(live)
        assert rebuilt.version == live.version

        assert {rebuilt.rating, rebuilt.ending, rebuilt.forked, rebuilt.abandoned} ==
                 {live.rating, live.ending, live.forked, live.abandoned}

        # Every link_taken names a Link the Nib shown just before it offered.
        reading.id
        |> Events.read_stream()
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn
          [
            %{type: "nib_shown", data: %{"links" => offered}},
            %{type: "link_taken", data: %{"link" => l}}
          ] ->
            assert l in offered

          [_, %{type: "link_taken"}] ->
            flunk("a link_taken not straight after a nib_shown")

          _ ->
            :ok
        end)
      end
    end
  end

  # An index picks an offered Link; text is whatever the client sent.
  defp try_link(i, reading) when is_integer(i) do
    case Reading.view(reading).links do
      [] -> reading
      links -> try_link(Enum.at(links, rem(i, length(links))).id, reading)
    end
  end

  defp try_link(id, reading) do
    case Reading.take(reading, id) do
      {:ok, reading} -> reading
      {:error, :not_offered} -> reading
    end
  end

  defp play_to_end(reading) do
    case Reading.view(reading) do
      %{done: true} ->
        reading

      %{links: [first | _]} ->
        {:ok, reading} = Reading.take(reading, first.id)
        play_to_end(reading)
    end
  end
end
