defmodule Inklinks.Catalog do
  @moduledoc """
  The Inklinks on offer: every IR file in `priv/inklinks/`.

  An Inklink's id is its file name without `.json`. The catalog reads only
  the IR's top level and its `config` settings, enough to list a work. What
  the Ink means is the engine's business.
  """

  defmodule Entry do
    @moduledoc "One Inklink in the catalog."
    @enforce_keys [:id, :path, :title]
    defstruct [:id, :path, :title, :ir, :kind, :mode, inquests: 0]

    @type t :: %__MODULE__{
            id: String.t(),
            path: Path.t(),
            title: String.t(),
            ir: String.t() | nil,
            kind: String.t() | nil,
            mode: String.t() | nil,
            inquests: non_neg_integer()
          }
  end

  @doc "Every Inklink found, ordered by title. Unreadable files are skipped."
  @spec list(Path.t()) :: [Entry.t()]
  def list(dir \\ dir()) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case read(path) do
        {:ok, entry} -> [entry]
        {:error, _} -> []
      end
    end)
    |> Enum.sort_by(&String.downcase(&1.title))
  end

  @doc "One Inklink by id."
  @spec fetch(String.t(), Path.t()) :: {:ok, Entry.t()} | :error
  def fetch(id, dir \\ dir()) do
    # Only ids the catalog itself listed: never a path built from input.
    case Enum.find(list(dir), &(&1.id == id)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  @doc "Reads one IR file's listing."
  @spec read(Path.t()) :: {:ok, Entry.t()} | {:error, term()}
  def read(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, %{"title" => title} = ir} when is_binary(title) <- JSON.decode(bytes) do
      config = List.wrap(ir["config"])

      {:ok,
       %Entry{
         id: Path.basename(path, ".json"),
         path: path,
         title: title,
         ir: ir["ir"],
         kind: setting(config, "kind"),
         mode: setting(config, "mode"),
         inquests: inquests(config)
       }}
    else
      {:ok, _} -> {:error, :not_an_inklink}
      {:error, reason} -> {:error, reason}
    end
  end

  defp setting(config, name) do
    Enum.find_value(config, fn
      %{"setting" => ^name, "value" => value} when is_binary(value) -> value
      _ -> nil
    end)
  end

  # An Inklink has Inquests only when its Inker declared them.
  defp inquests(config) do
    Enum.find_value(config, 0, fn
      %{"declare" => "resource", "id" => "inquests", "value" => n} when is_integer(n) and n > 0 ->
        n

      _ ->
        nil
    end)
  end

  defp dir, do: Application.app_dir(:inklinks, "priv/inklinks")
end
