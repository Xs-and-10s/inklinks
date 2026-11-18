defmodule Inklinks.Engine.Stub.Story do
  @moduledoc """
  An Inklink loaded for the stub: its passages by name, its declarations by
  id, and whatever this engine cannot play, found before anyone starts.

  The stub plays solo stories: Nibs, `go` Links, `[if]` and `~ when`, facts
  and lists. Anything else is named in `{:unsupported, reasons}` rather than
  guessed at, as the Rust interpreter does.
  """

  @enforce_keys [:title, :start, :pov, :passages, :declared]
  defstruct [:title, :start, :pov, :passages, :declared, :kind, :mode, inquests: 0, ir: nil]

  @type t :: %__MODULE__{}

  @effects ~w(set add strike remove move)
  @modifiers ~w(if unless else end once beat after)
  @inserts ["list", "value", "sound effect"]
  @operators ~w(get == != < > <= >= and or not neg + - * / mod str)
  @link_kinds ~w(go)

  @doc "Decodes and checks an Inklink's IR."
  @spec load(binary()) :: {:ok, t()} | {:error, {:unsupported, [String.t()]} | term()}
  def load(json) do
    with {:ok, %{"passages" => passages, "config" => config} = ir} <- decode(json) do
      story = build(ir, config, passages)

      case unsupported(story, config, passages) do
        [] -> {:ok, story}
        reasons -> {:error, {:unsupported, reasons}}
      end
    end
  end

  defp decode(json) do
    case JSON.decode(json) do
      {:ok, %{"ir" => _} = ir} -> {:ok, ir}
      {:ok, _} -> {:error, :not_an_inklink}
      {:error, reason} -> {:error, {:bad_json, reason}}
    end
  end

  defp build(ir, config, passages) do
    declared =
      (config ++ Enum.flat_map(passages, & &1["header"]))
      |> Enum.filter(&(is_map(&1) and Map.has_key?(&1, "declare") and Map.has_key?(&1, "id")))
      |> Map.new(&{&1["id"], &1})

    %__MODULE__{
      title: ir["title"],
      ir: ir["ir"],
      start: ir["start"],
      pov: config |> setting("pov") |> List.wrap() |> List.first(),
      kind: setting(config, "kind"),
      mode: setting(config, "mode"),
      inquests: inquests(declared),
      passages: Map.new(passages, &{&1["name"], &1}),
      declared: declared
    }
  end

  defp setting(config, name) do
    Enum.find_value(config, fn
      %{"setting" => ^name} = s -> s["value"]
      _ -> nil
    end)
  end

  defp inquests(%{"inquests" => %{"declare" => "resource", "value" => n}}) when is_integer(n),
    do: n

  defp inquests(_), do: 0

  # -- what the stub cannot play -------------------------------------------------

  defp unsupported(story, config, passages) do
    [
      if(story.mode not in [nil, "solo"], do: "#{story.mode} mode"),
      if(story.pov == nil, do: "a story with no pov"),
      if(not Map.has_key?(story.passages, story.start || ""), do: "a missing start passage"),
      Enum.map(config, &config_statement/1),
      Enum.map(passages, &passage_reasons/1)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Declarations and settings are fine; config-level effects and `on`
  # handlers are not something a story walker runs.
  defp config_statement(%{"on" => _}), do: "`on` handlers"
  defp config_statement(%{"let" => _}), do: "`let` in the config"
  defp config_statement(%{"checkpoint" => _}), do: "checkpoints"
  defp config_statement(%{"hint" => _}), do: "hints"
  defp config_statement(_), do: nil

  defp passage_reasons(%{"header" => header, "body" => body} = passage) do
    [
      if("lib" in passage["tags"], do: "`[lib]` passages"),
      Enum.map(header, &header_statement/1),
      Enum.map(body, &node_reasons/1)
    ]
  end

  defp header_statement(%{"setting" => "next"}), do: nil
  defp header_statement(%{"setting" => _}), do: nil
  defp header_statement(%{"declare" => _}), do: nil
  defp header_statement(%{"effect" => effect}), do: effect_reasons(effect)
  defp header_statement(%{"let" => _}), do: "`let`"
  defp header_statement(%{"get" => _}), do: "`get`"
  defp header_statement(%{"expect" => _}), do: nil
  defp header_statement(other), do: "`#{first_key(other)}` statements"

  defp node_reasons(%{"type" => "link"} = link) do
    [
      if(link["kind"] not in @link_kinds, do: "`#{link["kind"]}` Links"),
      if(link["cost"] not in [nil, []], do: "Links with a cost"),
      if(link["check"] != nil, do: "Links with a check"),
      expr_reasons(link["when"]),
      expr_reasons(link["hidden_until"]),
      Enum.map(link["effects"] || [], &effect_reasons/1)
    ]
  end

  defp node_reasons(%{"type" => "modifier", "parts" => parts}) do
    Enum.map(parts, fn part ->
      [
        if(part["name"] not in @modifiers, do: "the `[#{part["name"]}]` modifier"),
        expr_reasons(part["when"])
      ]
    end)
  end

  defp node_reasons(%{"type" => type, "paragraphs" => paragraphs})
       when type in ["prose", "speech"] do
    for paragraph <- paragraphs, part <- paragraph, is_map(part) do
      cond do
        Map.has_key?(part, "value") -> expr_reasons(part["value"])
        part["insert"] in @inserts -> nil
        true -> "the `{#{part["insert"]}}` insert"
      end
    end
  end

  defp node_reasons(%{"type" => type}), do: "`#{type}` nodes"

  defp effect_reasons(%{"do" => verb} = effect) do
    [
      if(verb not in @effects, do: "the `#{verb}` effect"),
      expr_reasons(effect["when"]),
      expr_reasons(effect["value"])
    ]
  end

  defp expr_reasons(nil), do: nil
  defp expr_reasons(value) when is_binary(value) or is_number(value) or is_boolean(value), do: nil
  defp expr_reasons(list) when is_list(list), do: Enum.map(list, &expr_reasons/1)

  defp expr_reasons(%{} = expr) do
    op = first_key(expr)

    if op in @operators do
      expr |> Map.values() |> Enum.map(&expr_reasons/1)
    else
      "`#{op}` in expressions"
    end
  end

  defp first_key(map), do: map |> Map.keys() |> List.first()
end
