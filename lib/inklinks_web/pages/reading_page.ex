defmodule InklinksWeb.ReadingPage do
  @moduledoc """
  The reader: one Nib at a time, and its Links.

  `GET /readings/:id` renders the page. Taking a Link is a Datastar event,
  `POST /readings/:id/_event/take:<link id>`; the answer is an SSE patch of
  the `#nib` article, inside a View Transition where the browser has them.

  A reading belongs to its reader. `mount/2` checks on GET and `authorize/2`
  checks before every event, because dstar runs them on separate routes.
  """
  use Dstar.Page

  import InklinksWeb.Ink

  alias Inklinks.Reading
  alias InklinksWeb.Layouts

  # -- GET -----------------------------------------------------------------------

  def mount(conn, %{"id" => id}) do
    case Reading.load(id, conn.assigns.reader_id) do
      {:ok, reading} ->
        view = Reading.view(reading)
        assign(conn, reading: reading, view: view, page_title: view.title)

      {:error, _} ->
        not_found(conn)
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app>
      <.nib reading={@reading} view={@view} />
    </Layouts.app>
    """
  end

  # -- events --------------------------------------------------------------------

  def authorize(conn, {:event, _event}) do
    case Reading.load(conn.path_params["id"], conn.assigns.reader_id) do
      {:ok, reading} -> assign(conn, :reading, reading)
      {:error, _} -> not_found(conn)
    end
  end

  def handle_event(conn, "take:" <> link_id, _signals) do
    reading =
      case Reading.take(conn.assigns.reading, link_id) do
        {:ok, reading} ->
          reading

        # A stale tab, or another tab got there first: show where the
        # reading really is.
        {:error, _} ->
          {:ok, reading} = Reading.load(conn.assigns.reading.id, conn.assigns.reader_id)
          reading
      end

    patch_nib(conn, reading)
  end

  defp patch_nib(conn, reading) do
    # Replace, not morph: a new element runs its data-init, so focus follows
    # every Link, not just the first.
    patch(conn, &nib/1, [reading: reading, view: Reading.view(reading), moved: true],
      mode: :replace,
      use_view_transitions: true
    )
  end

  # -- the Nib -------------------------------------------------------------------

  attr :reading, :map, required: true
  attr :view, :map, required: true
  attr :moved, :boolean, default: false

  @doc """
  The whole Nib, patched as one element. After a Link, focus moves to it
  and it scrolls into view, so a screen reader starts reading the new Ink.
  """
  def nib(assigns) do
    ~H"""
    <article
      id="nib"
      tabindex="-1"
      aria-labelledby="nib-title"
      data-nib={@view.nib}
      data-init={@moved && "el.focus({preventScroll: true}); el.scrollIntoView({block: 'start'})"}
    >
      <h1 id="nib-title">{@view.title}</h1>
      <.ink sections={@view.ink} />

      <nav :if={@view.links != []} aria-label="Links">
        <ul>
          <li :for={link <- @view.links}>
            <button type="button" data-on:click={event("take:" <> link.id)}>
              <.parts parts={link.label} />
            </button>
          </li>
        </ul>
      </nav>

      <footer :if={@view.done}>
        <p>The end.</p>
        <form method="post" action={"/inklinks/#{@reading.inklink_id}/readings"}>
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="again" value="true" />
          <button>Read again</button>
        </form>
        <a href="/">Back to the library</a>
      </footer>
    </article>
    """
  end

  defp not_found(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(404, "Not Found")
    |> Plug.Conn.halt()
  end
end
