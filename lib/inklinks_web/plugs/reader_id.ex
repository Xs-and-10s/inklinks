defmodule InklinksWeb.Plugs.ReaderId do
  @moduledoc """
  Gives every browser an anonymous reader id, until accounts exist.

  The id is a UUIDv7 kept in the signed session cookie, so a reader can see
  it but cannot forge another reader's. Clearing cookies makes a new reader:
  acceptable while Inquests cost nothing. When accounts arrive, a
  `reader_claimed` event will tie this id to the account.

  Sets `conn.assigns.reader_id`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case conn |> get_session(:reader_id) |> valid_id() do
      {:ok, id} ->
        assign(conn, :reader_id, id)

      :error ->
        id = Ecto.UUID.generate(version: 7)

        conn
        |> put_session(:reader_id, id)
        |> assign(:reader_id, id)
    end
  end

  # The cookie is signed, so a bad value means an old or foreign cookie, not
  # an attack. Start over rather than crash.
  defp valid_id(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp valid_id(_), do: :error
end
