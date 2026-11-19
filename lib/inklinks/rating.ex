defmodule Inklinks.Rating do
  @moduledoc """
  Ratings after a finale.

  When a reading reaches a `finale`, the box asks (`rating_asked`, recorded
  with the Nib, so a reload asks again until answered):

    * the ending, 1 to 5;
    * the Inklink overall, 1 to 5;
    * "your path", 1 to 5, only if the Linker took or declined a fork;
    * and under "More…", moments they visited that they would change, each
      with what they would change. "I wouldn't change a thing" is selected
      at first; "Add another" saves a moment and lets them pick the next.

  It is asked once per reading, and never for an ending this Linker has
  already rated, in any reading. Every score is optional; answering with
  nothing at all is the same as "Not now".
  """
  alias Inklinks.Reading

  @scores ~w(ending inklink path)
  @max_text 2_000

  @typedoc """
  The box's answers: `"ending"`, `"inklink"`, `"path"` (1 to 5, as numbers
  or strings); `"change_at"`, the version of a visited Nib's `nib_shown`,
  or `"none"` for "I wouldn't change a thing"; `"change_text"`; and
  `"more_opened"`, whether the Linker opened More… at all.
  """
  @type answers :: %{optional(String.t()) => term()}

  @doc "Done: the scores, and the moment selected now (if any)."
  @spec answer(Reading.t(), answers()) :: {:ok, Reading.t()} | {:error, :not_now}
  def answer(%Reading{rating: :asking} = reading, answers) do
    scores =
      for key <- @scores, key != "path" or reading.forked, into: %{} do
        {"#{key}_score", score(answers[key])}
      end

    moment = moment(reading, answers)

    if Enum.all?(Map.values(scores), &is_nil/1) and moment == [] and reading.wished == [] do
      dismiss(reading)
    else
      given = %{type: "rating_given", data: Map.put(scores, "ending", reading.ending)}
      Reading.record(reading, moment ++ [given])
    end
  end

  def answer(_reading, _answers), do: {:error, :not_now}

  @doc """
  "Add another": saves the selected moment and its text, and keeps the box
  open for the next. A moment can be saved once per reading.
  """
  @spec wish(Reading.t(), answers()) :: {:ok, Reading.t()} | {:error, :not_now | :no_moment}
  def wish(%Reading{rating: :asking} = reading, answers) do
    case change(reading, answers["change_at"], answers["change_text"]) do
      [] -> {:error, :no_moment}
      wished -> Reading.record(reading, wished)
    end
  end

  def wish(_reading, _answers), do: {:error, :not_now}

  @doc "\"Not now\", Escape, or an answer with nothing in it."
  @spec dismiss(Reading.t()) :: {:ok, Reading.t()} | {:error, :not_now}
  def dismiss(%Reading{rating: :asking} = reading) do
    Reading.record(reading, [%{type: "rating_dismissed", data: %{"ending" => reading.ending}}])
  end

  def dismiss(_reading), do: {:error, :not_now}

  @doc """
  The moments a Linker could say they would change: every Nib this reading
  showed where they chose something, oldest first, by what they chose, and
  whether they have already said so (`wished`).
  """
  @spec moments(Reading.t()) :: [
          %{at: pos_integer(), nib: String.t(), chose: String.t(), wished: boolean()}
        ]
  def moments(%Reading{nibs: nibs, wished: wished}) do
    for %{chose: chose} = visit <- Enum.reverse(nibs), is_binary(chose) do
      %{at: visit.version, nib: visit.nib, chose: chose, wished: visit.version in wished}
    end
  end

  # -- helpers -------------------------------------------------------------------

  # What Done records about moments: the selected one, or, if they opened
  # More… and left "I wouldn't change a thing" selected (having saved none),
  # that they would change nothing.
  defp moment(reading, answers) do
    case change(reading, answers["change_at"], answers["change_text"]) do
      [] ->
        if answers["change_at"] in ["none", nil, ""] and truthy?(answers["more_opened"]) and
             reading.wished == [] do
          [%{type: "nothing_to_change", data: %{"ending" => reading.ending}}]
        else
          []
        end

      wished ->
        wished
    end
  end

  defp truthy?(v), do: v in [true, "true"]

  defp score(n) when is_integer(n) and n in 1..5, do: n

  defp score(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> score(n)
      _ -> nil
    end
  end

  defp score(_), do: nil

  defp change(reading, at, text) do
    with {v, ""} <- Integer.parse(to_string(at || "")),
         %{wished: false} = moment <- Enum.find(moments(reading), &(&1.at == v)) do
      text = text |> to_string() |> String.trim() |> String.slice(0, @max_text)

      [
        %{
          type: "change_wished",
          data: %{
            "nib" => moment.nib,
            "back_to" => v,
            "chose" => moment.chose,
            "text" => if(text == "", do: nil, else: text)
          }
        }
      ]
    else
      _ -> []
    end
  end
end
