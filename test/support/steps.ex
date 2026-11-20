defmodule Inklinks.Steps do
  @moduledoc """
  Everything a Linker (or a forged request) might try on the Littlejon
  fixture, in any order: at the current Nib, or at an earlier one (the
  first earlier place, if any). Shared by the property tests.
  """
  import StreamData

  alias Inklinks.{Inquest, Reading}

  @doc "One step."
  def step do
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

  @doc "Ids worth trying: offered Links, forks, and one that is neither."
  def link_id do
    member_of(
      ~w(obey_at_thornbury watch_what_unfolds free_the_widow speak_in_her_ear keep_the_book
         burn_the_book on_to_the_fens south_to_the_fens on_to_halde nonsense)
    )
  end

  @doc "Runs a step. A refused step leaves the reading as it was."
  def run(:open, r), do: ok(Inquest.open(r), r)
  def run({:answer, text}, r), do: ok(Inquest.answer(r, text), r)
  def run({:look, id, earlier?}, r), do: ok(Inquest.look(r, id, at(r, earlier?)), r)
  def run({:take_fork, id}, r), do: ok(Inquest.take(r, id), r)
  def run({:want, id, earlier?}, r), do: ok(Inquest.want(r, id, at(r, earlier?)), r)
  def run({:answer_wanted, text}, r), do: ok(Inquest.answer_wanted(r, text), r)
  def run(:leave, r), do: ok(Inquest.leave(r), r)
  def run({:take, id}, r), do: ok(Reading.take(r, id), r)

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
end
