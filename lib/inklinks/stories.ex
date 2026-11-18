defmodule Inklinks.Stories do
  @moduledoc """
  Loaded Inklinks, cached: each IR file is handed to the engine's `load/1`
  once, and again only when the file changes.

  The cache is an ETS table, read by any process. This GenServer exists only
  to own the table. Two processes loading the same file at once both load
  it; the result is the same, and the last write wins.
  """
  use GenServer

  alias Inklinks.{Catalog, Engine}

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  @typedoc "An Inklink ready to play: its catalog entry, story, and IR digest."
  @type loaded :: %{entry: Catalog.Entry.t(), story: Engine.story(), sha256: String.t()}

  @doc """
  The Inklink with this catalog id, loaded. `{:error, {:unsupported, why}}`
  when the engine cannot play it.
  """
  @spec fetch(String.t()) :: {:ok, loaded()} | {:error, term()}
  def fetch(inklink_id) do
    with {:ok, entry} <- Catalog.fetch(inklink_id),
         {:ok, %File.Stat{mtime: mtime, size: size}} <- File.stat(entry.path) do
      key = {inklink_id, mtime, size}

      case :ets.lookup(@table, key) do
        [{^key, result}] -> result
        [] -> tap(load(entry), &:ets.insert(@table, {key, &1}))
      end
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load(entry) do
    bytes = File.read!(entry.path)

    case Engine.call(:load, [bytes]) do
      {:ok, story} ->
        {:ok,
         %{
           entry: entry,
           story: story,
           sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
