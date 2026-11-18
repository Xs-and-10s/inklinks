defmodule Inklinks.Inquest do
  @moduledoc """
  Inquests, flow D: ask first, then flip.

  An Inquest is a Linker asking the story to leave its canon where they are.
  The Inker may have hidden forks there; if not, the request is noted for
  the Inker and costs nothing.

  1. **Box first.** `open/1`, then `answer/2` with what the Linker would
     change (or `nil` to skip).
  2. **No fork here** (or no Inquests left): turned down, "Noted. The Inker
     will read this." Nothing is spent.
  3. **Forks here:** Inquest mode. `look/2` flips a canon Link to the fork
     that stands in for it, fetched from the engine only then. Looking is
     free. `take/2` takes a fork that was looked at, and spends one Inquest.
  4. A canon Link with **no fork**, chosen in Inquest mode, asks what the
     Linker wanted instead (`want/2`, then `answer_wanted/2`). Then Inquest
     mode ends and the Linker chooses; the canon Link is never followed for
     them.
  5. `leave/1` ends Inquest mode at any time.

  Scope: solo only (the engine refuses Inquests in cohort mode); only the
  current Nib's forks; per Linker, per Inklink, per reading (the budget
  lives in the reading's stream); only when the Inker declared them.

  Every step is recorded (docs/events.md). Where flow D stands is projected
  from those events (`Reading.inquest`), so a reload lands in the same place.
  """
  alias Inklinks.{Engine, Reading}

  @max_text 2_000

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

        not Engine.call(:forks?, [reading.loaded.story, reading.state]) ->
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

  @doc """
  Flips a canon Link: the fork that stands in for it, or `:no_fork`. The
  first look at each fork is recorded; looking again is free and silent.
  """
  @spec look(Reading.t(), String.t()) ::
          {:ok, Reading.t(), {:fork, Engine.link()} | :no_fork} | error()
  def look(%Reading{inquest: :mode} = reading, canon) do
    view = Reading.view(reading)

    cond do
      not Enum.any?(view.links, &(&1.id == canon)) ->
        {:error, :not_offered}

      true ->
        case Engine.call(:fork, [reading.loaded.story, reading.state, canon]) do
          :none ->
            {:ok, reading, :no_fork}

          {:ok, fork} when is_map_key(reading.looked, fork.id) ->
            {:ok, reading, {:fork, fork}}

          {:ok, fork} ->
            looked = %{
              type: "fork_looked",
              data: %{
                "nib" => view.nib,
                "canon" => canon,
                "fork" => fork.id,
                "label" => Reading.plain(fork.label)
              }
            }

            with {:ok, reading} <- Reading.record(reading, [looked]) do
              {:ok, reading, {:fork, fork}}
            end
        end
    end
  end

  def look(_reading, _canon), do: {:error, :not_now}

  @doc """
  Takes a fork the Linker has looked at, and spends one Inquest. A fork
  never looked at cannot be taken: its id is not something the page knew.
  """
  @spec take(Reading.t(), String.t()) :: {:ok, Reading.t()} | error()
  def take(%Reading{inquest: :mode} = reading, fork) do
    with {:ok, canon} <- Map.fetch(reading.looked, fork) |> or_error(:not_offered),
         true <- Reading.remaining(reading) > 0 || {:error, :none_left},
         before = Reading.view(reading),
         {:ok, %{label: label}} <-
           Engine.call(:fork, [reading.loaded.story, reading.state, canon]),
         {:ok, state} <- Engine.call(:take_fork, [reading.loaded.story, reading.state, fork]) do
      taken = %{
        type: "fork_taken",
        data: %{
          "nib" => before.nib,
          "canon" => canon,
          "fork" => fork,
          "label" => Reading.plain(label)
        }
      }

      declined =
        for {other, other_canon} <- Enum.sort(reading.looked), other != fork do
          %{
            type: "fork_declined",
            data: %{
              "nib" => before.nib,
              "canon" => other_canon,
              "fork" => other,
              "by" => "took_another_fork"
            }
          }
        end

      after_fork = %{reading | state: state}
      Reading.record(after_fork, [taken | declined] ++ Reading.shown(Reading.view(after_fork)))
    else
      :none -> {:error, :not_offered}
      {:error, reason} -> {:error, reason}
    end
  end

  def take(_reading, _fork), do: {:error, :not_now}

  @doc """
  A canon Link chosen in Inquest mode. With no fork, it asks what the
  Linker wanted instead (`:asked`; then `answer_wanted/2`). With a fork, it
  flips, as `look/2` does, and returns the fork.
  """
  @spec want(Reading.t(), String.t()) ::
          {:ok, Reading.t(), :asked | {:fork, Engine.link()}} | error()
  def want(%Reading{inquest: :mode} = reading, canon) do
    case look(reading, canon) do
      {:ok, reading, :no_fork} ->
        opened = %{
          type: "wanted_instead_opened",
          data: %{"nib" => Reading.view(reading).nib, "canon" => canon}
        }

        with {:ok, reading} <- Reading.record(reading, [opened]) do
          {:ok, reading, :asked}
        end

      other ->
        other
    end
  end

  def want(_reading, _canon), do: {:error, :not_now}

  @doc """
  Answers "what did you want instead", with text or `nil` (Skip). Inquest
  mode then ends; the Linker chooses a Link themselves.
  """
  @spec answer_wanted(Reading.t(), String.t() | nil) :: {:ok, Reading.t()} | error()
  def answer_wanted(%Reading{inquest: {:wanting, canon}} = reading, text) do
    nib = Reading.view(reading).nib

    said =
      case clean(text) do
        nil ->
          %{type: "wanted_instead_skipped", data: %{"nib" => nib, "canon" => canon}}

        text ->
          %{
            type: "wanted_instead_submitted",
            data: %{"nib" => nib, "canon" => canon, "text" => text}
          }
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
