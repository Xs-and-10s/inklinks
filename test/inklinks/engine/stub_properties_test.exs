defmodule Inklinks.Engine.StubPropertiesTest do
  @moduledoc """
  What holds for every reading of every Inklink the stub plays, whatever the
  Linker chooses and whatever they try to choose.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Inklinks.Engine.Stub

  setup_all do
    {:ok, story} = Stub.load(File.read!("priv/inklinks/ex3-the-fall-of-the-old-regime.json"))

    every_link_id =
      for {_, passage} <- story.passages,
          %{"type" => "link", "id" => id} <- passage["body"],
          do: id

    %{story: story, every_link_id: every_link_id}
  end

  property "a reader can never take a Link the IR doesn't offer",
           %{story: story, every_link_id: every_link_id} do
    check all(
            seed <- positive_integer(),
            attempts <- list_of(attempt(every_link_id), max_length: 40)
          ) do
      {:ok, w} = Stub.start(story, seed)

      Enum.reduce(attempts, w, fn attempt, w ->
        view = Stub.view(story, w)
        id = pick(attempt, view)
        offered? = Enum.any?(view.links, &(&1.id == id))

        case Stub.take_link(story, w, id) do
          {:ok, next} ->
            assert offered?, "took #{inspect(id)}, which #{view.nib} does not offer"
            next

          {:error, :not_offered} ->
            refute offered?, "refused #{inspect(id)}, which #{view.nib} offers"
            # A refused Link changes nothing.
            assert Stub.view(story, w) == view
            w
        end
      end)
    end
  end

  property "the same seed and the same Links always tell the same story", %{story: story} do
    check all(
            seed <- positive_integer(),
            choices <- list_of(non_negative_integer(), max_length: 15)
          ) do
      assert walk(story, seed, choices) == walk(story, seed, choices)
    end
  end

  property "every reading of Ex 3 ends at the list, within a dozen Links", %{story: story} do
    check all(
            seed <- positive_integer(),
            choices <- list_of(non_negative_integer(), length: 12)
          ) do
      views = walk(story, seed, choices)
      final = List.last(views)

      assert final.done
      assert final.ending == "the_list"
      assert Enum.all?(Enum.drop(views, -1), &(not &1.done))
    end
  end

  # An attempt is an offered Link (by index), any Link in the IR, or junk.
  defp attempt(every_link_id) do
    one_of([
      tuple({constant(:offered), non_negative_integer()}),
      tuple({constant(:any), member_of(every_link_id)}),
      tuple({constant(:junk), string(:printable, max_length: 12)})
    ])
  end

  defp pick({:offered, i}, %{links: []}), do: "nothing-#{i}"
  defp pick({:offered, i}, %{links: links}), do: Enum.at(links, rem(i, length(links))).id
  defp pick({_, id}, _view), do: id

  # The views a reading passes through, choosing by index, until it ends.
  defp walk(story, seed, choices) do
    {:ok, w} = Stub.start(story, seed)

    {views, _} =
      Enum.reduce_while(choices, {[Stub.view(story, w)], w}, fn i, {views, w} ->
        case Stub.view(story, w) do
          %{done: true} ->
            {:halt, {views, w}}

          %{links: links} ->
            {:ok, w} = Stub.take_link(story, w, Enum.at(links, rem(i, length(links))).id)
            {:cont, {views ++ [Stub.view(story, w)], w}}
        end
      end)

    views
  end
end
