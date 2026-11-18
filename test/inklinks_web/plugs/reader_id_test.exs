defmodule InklinksWeb.Plugs.ReaderIdTest do
  use InklinksWeb.ConnCase, async: true

  describe "a first visit" do
    test "gives the browser a UUIDv7 reader id, kept in the session", %{conn: conn} do
      conn = get(conn, ~p"/")

      id = conn.assigns.reader_id
      assert get_session(conn, :reader_id) == id
      assert {:ok, <<_::48, 7::4, _::76>>} = Ecto.UUID.dump(id)
    end
  end

  describe "a return visit with the same cookie" do
    test "keeps the same reader id", %{conn: conn} do
      first = get(conn, ~p"/")

      again = first |> recycle() |> get(~p"/")

      assert again.assigns.reader_id == first.assigns.reader_id
    end
  end

  describe "a session holding something that is not a reader id" do
    test "starts a new reader rather than failing", %{conn: conn} do
      conn =
        conn
        |> init_test_session(reader_id: "not-a-uuid")
        |> get(~p"/")

      assert {:ok, _} = Ecto.UUID.cast(conn.assigns.reader_id)
      refute conn.assigns.reader_id == "not-a-uuid"
    end
  end
end
