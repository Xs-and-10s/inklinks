defmodule Inklinks.Rating do
  @moduledoc """
  Ratings after a finale.

  When a reading reaches a `finale`, the box asks (`rating_asked`, recorded
  with the Nib, so a reload asks again until answered):

    * the ending, 1 to 5;
    * the Inklink overall, 1 to 5;
    * "your path", 1 to 5, only if the Linker took or declined a fork;
    * and under "More…", a moment they visited that they would change, with
      what they would change.

  It is asked once per reading, and never for an ending this Linker has
  already rated, in any reading. Every score is optional; answering with
  nothing at all is the same as "Not now".
  """
  alias Inklinks.Reading

  @scores ~w(ending inklink path)
  @max_text 2_000

  @type answers :: %{
          optional(String.t()) => String.t() | integer() | nil
        }

  @doc """
  Answers the box. `answers` holds `"ending"`, `"inklink"`, `"path"` (1 to
  5, as numbers or strings), and optionally `"change_at"` (the version of a
  visited Nib's `nib_shown`) with `"change_text"`.
  """
  @spec answer(Reading.t(), answers()) :: {:ok, Reading.t()} | {:error, :not_now}
  def answer(%Reading{rating: :asking} = reading, answers) do
    scores =
      for key <- @scores, key != "path" or reading.forked, into: %{} do
        {key, score(answers[key])}
      end

    change = change(reading, answers["change_at"], answers["change_text"])

    cond do
      Enum.all?(Map.values(scores), &is_nil/1) and change == [] ->
        dismiss(reading)

      true ->
        # Stored as ending_score, inklink_score, path_score, beside the
        # ending's name.
        scores = Map.new(scores, fn {key, n} -> {"#{key}_score", n} end)
        given = %{type: "rating_given", data: Map.put(scores, "ending", reading.ending)}

        Reading.record(reading, [given | change])
    end
  end

  def answer(_reading, _answers), do: {:error, :not_now}

  @doc "\"Not now\", Escape, or an empty answer."
  @spec dismiss(Reading.t()) :: {:ok, Reading.t()} | {:error, :not_now}
  def dismiss(%Reading{rating: :asking} = reading) do
    Reading.record(reading, [%{type: "rating_dismissed", data: %{"ending" => reading.ending}}])
  end

  def dismiss(_reading), do: {:error, :not_now}

  @doc """
  The moments a Linker could say they would change: every Nib this reading
  showed where they chose something, oldest first, by what they chose.
  """
  @spec moments(Reading.t()) :: [%{at: pos_integer(), nib: String.t(), chose: String.t()}]
  def moments(%Reading{nibs: nibs}) do
    for %{chose: chose} = visit <- Enum.reverse(nibs), is_binary(chose) do
      %{at: visit.version, nib: visit.nib, chose: chose}
    end
  end

  # -- helpers -------------------------------------------------------------------

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
         %{} = moment <- Enum.find(moments(reading), &(&1.at == v)) do
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
