defmodule Inklinks.Inquest do
  @moduledoc """
  Inquests, flow D: ask first, then flip.

  An Inquest is a Linker asking the story to leave its canon where they are.
  The Inker may have hidden forks there; if not, the request is noted for
  the Inker and costs nothing.

  1. **Box first.** `open/1`, then `answer/2` with what the Linker would
     change (or `nil` to skip).
  2. **No fork to look at** (or no Inquests left): turned down, "Noted. The
     Inker will read this." Nothing is spent.
  3. **Forks to look at:** Inquest mode. `look/3` flips an offered Link to
     the forks that stand in for it, in the Inker's order, fetched from the
     engine only then. Looking is free. `take/2` takes a fork that was looked
     at, and spends one Inquest. Taking a fork moves on, which ends Inquest
     mode.
  4. An offered Link with **no fork**, chosen in Inquest mode, asks what the
     Linker wanted instead (`want/3`, then `answer_wanted/2`). Then Inquest
     mode ends and the Linker chooses; the Link is never followed for them.
  5. `leave/1` ends Inquest mode at any time.

  **Where an Inquest looks.** The current Nib's forks, and the forks of
  earlier passages that the Inker marked to be asked for from this Nib
  (`~ inquest from ch3`). For those, the page shows the earlier Nib's
  offered Links as the Linker saw them, and taking a fork goes back to that
  visit (`Reading.places/1`): the reading is replayed to it, then the fork
  is taken. Inquests already spent stay spent; they are the Linker's.

  Scope: solo only (the engine refuses Inquests in cohort mode); per
  Linker, per Inklink, per reading (the budget lives in the reading's
  stream); only when the Inker declared them.

  Every step is recorded (docs/events.md). Where flow D stands is projected
  from those events (`Reading.inquest`), so a reload lands in the same place.
  """
  alias Inklinks.{Engine, Reading}

  @max_text 2_000

  @type at :: pos_integer() | nil
  @type error :: {:error, :not_now | :not_offered | :none_left | term()}

  @doc "Opens the box: \"What would you change here?\""
  @spec open(Reading.t()) :: {:ok, Reading.t()} | error()
  def open(%Reading{inquest: :none, budget: budget} = reading) when budget > 0 do
    view = Reading.view(reading)

    if view.done do
      {:error, :not_now}
    else
      Reading.record(reading, [
        %{
          type: "inquest_opened",
          data: %{"nib" => view.nib, "remaining" => Reading.remaining(reading)}
        }
      ])
    end
  end

  def open(_reading), do: {:error, :not_now}

  @doc """
  Answers the box, with text or `nil` (Skip). Returns what happened:
  `:noted` (turned down, nothing spent) or `:inquest_mode`.
  """
  @spec answer(Reading.t(), String.t() | nil) ::
          {:ok, Reading.t(), :noted | :inquest_mode} | error()
  def answer(%Reading{inquest: :asking} = reading, text) do
    nib = Reading.view(reading).nib

    said =
      case clean(text) do
        nil -> %{type: "inquest_skipped", data: %{"nib" => nib}}
        text -> %{type: "inquest_submitted", data: %{"nib" => nib, "text" => text}}
      end

    {outcome, event} =
      cond do
        Reading.remaining(reading) == 0 ->
          {:noted, turned_down(nib, "none_left")}

        not forks_anywhere?(reading, nib) ->
          {:noted, turned_down(nib, "no_forks")}

        true ->
          {:inquest_mode,
           %{
             type: "inquest_mode_entered",
             data: %{"nib" => nib, "remaining" => Reading.remaining(reading)}
           }}
      end

    with {:ok, reading} <- Reading.record(reading, [said, event]) do
      {:ok, reading, outcome}
    end
  end

  def answer(_reading, _text), do: {:error, :not_now}

  defp forks_anywhere?(reading, nib) do
    Enum.any?(
      Reading.places(reading),
      &Engine.call(:forks?, [reading.loaded.story, &1.state, nib])
    )
  end

  @doc """
  Flips an offered Link to the forks that stand in for it, in the Inker's
  order, or `:no_forks`. `at` is `nil` for the current Nib, or the version of
  an earlier visit from `Reading.places/1`. The first look at each fork is
  recorded; looking again is free and silent.
  """
  @spec look(Reading.t(), String.t(), at()) ::
          {:ok, Reading.t(), {:forks, [Engine.link()]} | :no_forks} | error()
  def look(reading, link, at \\ nil)

  def look(%Reading{inquest: :mode} = reading, link, at) do
    nib = Reading.view(reading).nib

    with {:ok, place} <- place(reading, at),
         true <- offered?(reading, place, link) || {:error, :not_offered} do
      case Engine.call(:forks, [reading.loaded.story, place.state, link, nib]) do
        [] ->
          {:ok, reading, :no_forks}

        forks ->
          new =
            for fork <- forks, not Map.has_key?(reading.looked, fork.id) do
              data = %{
                "nib" => nib,
                "link" => link,
                "fork" => fork.id,
                "label" => Reading.plain(fork.label)
              }

              %{type: "fork_looked", data: Reading.located(reading, at, data)}
            end

          with {:ok, reading} <- record_if_any(reading, new) do
            {:ok, reading, {:forks, forks}}
          end
      end
    end
  end

  def look(_reading, _link, _at), do: {:error, :not_now}

  @doc """
  Takes a fork the Linker has looked at, and spends one Inquest. A fork
  never looked at cannot be taken: its id is not something the page knew.
  The other forks looked at are declined.
  """
  @spec take(Reading.t(), String.t()) :: {:ok, Reading.t()} | error()
  def take(%Reading{inquest: :mode} = reading, fork) do
    with {:ok, look} <- Map.fetch(reading.looked, fork) |> or_error(:not_offered),
         true <- Reading.remaining(reading) > 0 || {:error, :none_left},
         nib = Reading.view(reading).nib,
         from = Reading.state_at(reading, look.at),
         %{label: label} <-
           Enum.find(
             Engine.call(:forks, [reading.loaded.story, from, look.link, nib]),
             &(&1.id == fork)
           ) ||
             {:error, :not_offered},
         {:ok, state} <- Engine.call(:take_fork, [reading.loaded.story, from, fork]) do
      data = %{"nib" => nib, "link" => look.link, "fork" => fork, "label" => Reading.plain(label)}
      taken = %{type: "fork_taken", data: Reading.located(reading, look.at, data)}
      declined = Reading.declined(reading, "took_another_fork", fork)

      # Taking a fork puts "your path" in the ratings box, even when the fork
      # leads straight to a finale.
      after_fork = %{reading | state: state, forked: true}

      Reading.record(
        after_fork,
        [taken | declined] ++ Reading.shown(after_fork, Reading.view(after_fork))
      )
    end
  end

  def take(_reading, _fork), do: {:error, :not_now}

  @doc """
  An offered Link chosen in Inquest mode. With no fork, it asks what the
  Linker wanted instead (`:asked`; then `answer_wanted/2`). With forks, it
  flips, as `look/3` does.
  """
  @spec want(Reading.t(), String.t(), at()) ::
          {:ok, Reading.t(), :asked | {:forks, [Engine.link()]}} | error()
  def want(reading, link, at \\ nil)

  def want(%Reading{inquest: :mode} = reading, link, at) do
    case look(reading, link, at) do
      {:ok, reading, :no_forks} ->
        data = Reading.located(reading, at, %{"nib" => Reading.view(reading).nib, "link" => link})

        with {:ok, reading} <-
               Reading.record(reading, [%{type: "wanted_instead_opened", data: data}]) do
          {:ok, reading, :asked}
        end

      other ->
        other
    end
  end

  def want(_reading, _link, _at), do: {:error, :not_now}

  @doc """
  Answers "what did you want instead", with text or `nil` (Skip). Inquest
  mode then ends; the Linker chooses a Link themselves.
  """
  @spec answer_wanted(Reading.t(), String.t() | nil) :: {:ok, Reading.t()} | error()
  def answer_wanted(%Reading{inquest: {:wanting, link, at}} = reading, text) do
    base = Reading.located(reading, at, %{"nib" => Reading.view(reading).nib, "link" => link})

    said =
      case clean(text) do
        nil -> %{type: "wanted_instead_skipped", data: base}
        text -> %{type: "wanted_instead_submitted", data: Map.put(base, "text", text)}
      end

    Reading.record(reading, [said | Reading.leaving(reading, "wanted_instead")])
  end

  def answer_wanted(_reading, _text), do: {:error, :not_now}

  @doc "Leaves Inquest mode without taking a fork. Forks looked at are declined."
  @spec leave(Reading.t()) :: {:ok, Reading.t()} | error()
  def leave(%Reading{inquest: :mode} = reading),
    do: Reading.record(reading, Reading.leaving(reading, "left"))

  def leave(_reading), do: {:error, :not_now}

  # -- helpers -------------------------------------------------------------------

  defp place(reading, at) do
    case Enum.find(Reading.places(reading), &(&1.at == at)) do
      nil -> {:error, :not_offered}
      place -> {:ok, place}
    end
  end

  defp offered?(reading, place, link) do
    view = Engine.call(:view, [reading.loaded.story, place.state])
    Enum.any?(view.links, &(&1.id == link))
  end

  defp record_if_any(reading, []), do: {:ok, reading}
  defp record_if_any(reading, events), do: Reading.record(reading, events)

  defp turned_down(nib, reason),
    do: %{type: "inquest_turned_down", data: %{"nib" => nib, "reason" => reason}}

  # Free text: trimmed, capped, and nil when there is nothing to keep.
  defp clean(nil), do: nil

  defp clean(text) when is_binary(text) do
    case text |> String.trim() |> String.slice(0, @max_text) do
      "" -> nil
      text -> text
    end
  end

  defp clean(_), do: nil

  defp or_error({:ok, value}, _reason), do: {:ok, value}
  defp or_error(:error, reason), do: {:error, reason}
end
