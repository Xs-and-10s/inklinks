defmodule Inklinks.Engine.StubEx3Test do
  @moduledoc """
  Ex 3, The Fall of the Old Regime, played through the stub.

  These are the compiler's own Ex 3 tests
  (inkjot-compiler-rust, examples/tests/ex3-the-fall-of-the-old-regime.tests.twee),
  translated one for one: the stub must tell the story the interpreter tells.
  `expect: the_list.has(x)` becomes a check on the list the finale shows.
  """
  use ExUnit.Case, async: true

  alias Inklinks.Engine.Stub
  import Inklinks.ViewText

  setup_all do
    {:ok, story} = Stub.load(File.read!("priv/inklinks/ex3-the-fall-of-the-old-regime.json"))
    %{story: story}
  end

  test "the shortest path to the end", %{story: story} do
    w = begin(story)
    assert text(Stub.view(story, w)) =~ "your name is Skittles"
    assert "“They named me Skittles.”" in labels(story, w)

    w = choose(story, w, "“They named me Skittles.”")
    assert text(Stub.view(story, w)) =~ "It goes on twice."

    w =
      choose(story, w, [
        "Run",
        "The cat flap bangs",
        "Go and meet the Round One",
        "Ask him nicely"
      ])

    assert text(Stub.view(story, w)) =~ "You jump on."

    w = choose(story, w, ["The coup begins", "Curl up in the middle"])
    shown = text(Stub.view(story, w))
    assert shown =~ "A centrist. I knew it."
    assert shown =~ "On 8 charges"

    w = choose(story, w, "The end")
    view = Stub.view(story, w)
    assert text(view) =~ "~~the Round One~~"
    assert text(view) =~ "Leo (pending)"
    assert %{ending: "the_list", done: true, links: []} = view
  end

  test "the chin comes back in the last scene", %{story: story} do
    w = choose(story, begin(story), "“Nothing. They’re nice. One of them scratched my chin.”")
    assert text(Stub.view(story, w)) =~ "Scratched. Your. Chin."

    w =
      choose(story, w, [
        "Run",
        "The cat flap bangs",
        "Go and meet the Round One",
        "Press the big button",
        "The coup begins"
      ])

    shown = text(Stub.view(story, w))
    assert shown =~ "I told you it was good."
    assert shown =~ "You are still on the list."

    assert on_the_list?(story, w, "Skittles (watch)")
  end

  test "without the chin there is no callback", %{story: story} do
    w = choose(story, begin(story), "“They put me in a box with a handle.”")
    assert text(Stub.view(story, w)) =~ "We do not speak of recycling day."

    w =
      choose(story, w, [
        "Run",
        "The cat flap bangs",
        "Go and meet the Round One",
        "Press the big button",
        "The coup begins"
      ])

    refute text(Stub.view(story, w)) =~ "I told you it was good."
  end

  test "holding the line puts the kitten on the list", %{story: story} do
    w =
      choose(story, begin(story), [
        "“They named me Skittles.”",
        "“We hold the line! No treats from the regime!”"
      ])

    assert text(Stub.view(story, w)) =~
             "The kitten said “hold the line” and was first to the bag."

    assert on_the_list?(story, w, "Skittles (pending)")
    assert on_the_list?(story, w, "Biscuit")
  end

  test "spying does not", %{story: story} do
    w = choose(story, begin(story), ["“They named me Skittles.”", "“I’ll go. Just to spy.”"])
    refute text(Stub.view(story, w)) =~ "The kitten said “hold the line”"

    refute on_the_list?(story, w, "Skittles")
    assert on_the_list?(story, w, "Biscuit")
  end

  test "sitting on the roomba skips the jump", %{story: story} do
    w =
      choose(story, begin(story), [
        "“They named me Skittles.”",
        "Run",
        "The cat flap bangs",
        "Go and meet the Round One",
        "Sit on him"
      ])

    shown = text(Stub.view(story, w))
    assert shown =~ "Something under you goes click."
    refute shown =~ "You jump on."
  end

  test "lenny names his successor", %{story: story} do
    w = choose(story, begin(story), ["“They named me Skittles.”", "Run", "The cat flap bangs"])
    shown = text(Stub.view(story, w))
    assert shown =~ "I name… the Round One."
    assert shown =~ "It is in pen."
  end

  test "the button goes on the list", %{story: story} do
    w =
      choose(story, begin(story), [
        "“They named me Skittles.”",
        "Run",
        "The cat flap bangs",
        "Go and meet the Round One",
        "Ask him nicely",
        "The coup begins",
        "Attack the button on her cardigan"
      ])

    assert text(Stub.view(story, w)) =~ "I’m winning!"
    assert on_the_list?(story, w, "the button")
    assert on_the_list?(story, w, "Skittles’s forehead")
  end

  test "a step through an act passage shows both passages, in order", %{story: story} do
    view = Stub.view(story, choose(story, begin(story), "“They named me Skittles.”"))

    assert Enum.map(view.ink, & &1.passage) == ["arrival:name", "trial"]
    assert view.passed == ["arrival:name"]
    assert view.nib == "trial"
  end

  # -- helpers ---------------------------------------------------------------

  defp begin(story) do
    {:ok, w} = Stub.start(story, 1)
    w
  end

  defp labels(story, w), do: story |> Stub.view(w) |> Map.fetch!(:links) |> Enum.map(&label/1)

  defp choose(story, w, labels) when is_list(labels),
    do: Enum.reduce(labels, w, &choose(story, &2, &1))

  defp choose(story, w, wanted) do
    view = Stub.view(story, w)

    link =
      Enum.find(view.links, &(label(&1) == wanted)) ||
        flunk("no Link #{inspect(wanted)} in #{inspect(labels(story, w))}")

    {:ok, w} = Stub.take_link(story, w, link.id)
    w
  end

  # Play on to the finale by the first Link each time, and read the list.
  defp on_the_list?(story, w, entry) do
    final = finish(story, w)
    final |> text() |> String.split("\n") |> Enum.any?(&(&1 == entry))
  end

  defp finish(story, w) do
    case Stub.view(story, w) do
      %{done: true} = view ->
        view

      %{links: [first | _]} ->
        {:ok, w} = Stub.take_link(story, w, first.id)
        finish(story, w)
    end
  end
end
