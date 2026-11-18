defmodule InklinksWeb.ReadingPage do
  @moduledoc """
  The reader: one Nib at a time, its Links, and Inquests (flow D).

  `GET /readings/:id` renders the page. Everything else is a Datastar event,
  `POST /readings/:id/_event/<name>`, answered with SSE patches:

  | Event | Does |
  |---|---|
  | `take:<link>` | takes a canon Link; the next Nib replaces `#nib` in a View Transition |
  | `inquest` | opens the box: "What would you change here?" |
  | `inquest-answer`, `inquest-skip` | answers it: noted, or Inquest mode |
  | `look:<link>`, `unlook:<link>` | flips a canon Link to its fork and back (pointer or keyboard focus) |
  | `tap:<link>` | a click or tap in Inquest mode: flips, or asks what they wanted instead |
  | `take-fork:<fork>` | takes a fork that was flipped to; spends one Inquest |
  | `wanted-answer`, `wanted-skip` | answers "what did you want instead", then leaves Inquest mode |
  | `leave` | leaves Inquest mode (also Escape) |

  Forks are never in the page until a Linker flips to one: the server
  renders canon Links only, and a fork's label arrives in the patch that
  answers its flip. Announcements go to one `role=status` region outside
  the Nib, so it survives every patch.

  A reading belongs to its reader. `mount/2` checks on GET and `authorize/2`
  before every event, because dstar runs them on separate routes.
  """
  use Dstar.Page

  import InklinksWeb.Ink

  alias Inklinks.{Inquest, Reading}
  alias InklinksWeb.Layouts

  # -- GET -----------------------------------------------------------------------

  def mount(conn, %{"id" => id}) do
    case Reading.load(id, conn.assigns.reader_id) do
      {:ok, reading} -> assign(conn, reading: reading, page_title: Reading.view(reading).title)
      {:error, _} -> not_found(conn)
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app>
      <.nib reading={@reading} />
      <.announce text="" />
      <.dialogs reading={@reading} />
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

  def handle_event(conn, event, signals) do
    reading = conn.assigns.reading

    case run(event, reading, signals) do
      {:ok, patches} -> Enum.reduce(patches, conn, &apply_patch/2)
      # A stale tab, a forged request, or another tab got there first: show
      # where the reading really is.
      {:error, _} -> resync(conn, reading)
    end
  end

  defp run("take:" <> link, reading, _) do
    with {:ok, reading} <- Reading.take(reading, link) do
      {:ok, [:close_dialogs, {:nib, reading, :article}, {:announce, ""}]}
    end
  end

  defp run("inquest", reading, _) do
    with {:ok, reading} <- Inquest.open(reading) do
      {:ok, [{:dialogs, reading}]}
    end
  end

  defp run("inquest-answer", reading, signals), do: answer(reading, signals["wanted"])
  defp run("inquest-skip", reading, _), do: answer(reading, nil)

  defp run("look:" <> link, reading, _) do
    with {:ok, reading, found} <- Inquest.look(reading, link),
         do: {:ok, flipped(reading, link, found)}
  end

  defp run("unlook:" <> link, reading, _) do
    if reading.inquest == :mode,
      do: {:ok, [{:link, reading, link, :default}, {:announce, ""}]},
      else: {:error, :not_now}
  end

  defp run("tap:" <> link, reading, _) do
    case Inquest.want(reading, link) do
      {:ok, reading, :asked} -> {:ok, [{:dialogs, reading}]}
      {:ok, reading, found} -> {:ok, flipped(reading, link, found)}
      error -> error
    end
  end

  defp run("take-fork:" <> fork, reading, _) do
    with {:ok, reading} <- Inquest.take(reading, fork) do
      left = Reading.remaining(reading)

      {:ok,
       [{:nib, reading, :article}, {:announce, "You took another path. #{inquests(left)} left."}]}
    end
  end

  defp run("wanted-answer", reading, signals), do: wanted(reading, signals["wanted"])
  defp run("wanted-skip", reading, _), do: wanted(reading, nil)

  defp run("leave", reading, _) do
    with {:ok, reading} <- Inquest.leave(reading) do
      {:ok, [{:nib, reading, :first_link}, {:announce, "Inquest mode off."}]}
    end
  end

  defp run(_event, _reading, _), do: {:error, :unknown_event}

  defp answer(reading, text) do
    with {:ok, reading, outcome} <- Inquest.answer(reading, text) do
      said =
        case outcome do
          :noted ->
            "Noted. The Inker will read this."

          :inquest_mode ->
            "Inquest mode. Point at a Link, or move to it with Tab, to see whether another " <>
              "path hides behind it. Escape leaves Inquest mode."
        end

      {:ok, [:close_dialogs, :clear_text, {:nib, reading, :first_link}, {:announce, said}]}
    end
  end

  defp wanted(reading, text) do
    with {:ok, reading} <- Inquest.answer_wanted(reading, text) do
      {:ok,
       [
         :close_dialogs,
         :clear_text,
         {:nib, reading, :first_link},
         {:announce, "Noted. Choose a Link."}
       ]}
    end
  end

  defp flipped(reading, link, {:fork, fork}) do
    said =
      "Another path: #{Reading.plain(fork.label)}. Take it to spend one Inquest " <>
        "(#{inquests(Reading.remaining(reading))} left)."

    [{:link, reading, link, {:fork, fork}}, {:announce, said}]
  end

  # No announcement: the Link now says so itself, in its own label, so a
  # quick Tab across several Links cannot leave a stale message behind.
  defp flipped(reading, link, :no_fork), do: [{:link, reading, link, :plain}]

  defp inquests(1), do: "1 Inquest"
  defp inquests(n), do: "#{n} Inquests"

  # -- patches -------------------------------------------------------------------

  defp apply_patch({:nib, reading, focus}, conn) do
    patch(conn, &nib/1, [reading: reading, focus: focus],
      mode: :replace,
      use_view_transitions: true
    )
  end

  defp apply_patch({:link, reading, link, state}, conn) do
    view = Reading.view(reading)

    case Enum.find_index(view.links, &(&1.id == link)) do
      nil ->
        conn

      i ->
        assigns = [link: Enum.at(view.links, i), index: i, mode: true, state: state]
        patch(conn, &link_item/1, assigns, use_view_transitions: true)
    end
  end

  defp apply_patch({:dialogs, reading}, conn), do: patch(conn, &dialogs/1, reading: reading)
  defp apply_patch(:close_dialogs, conn), do: patch(conn, &dialogs/1, reading: nil)
  defp apply_patch({:announce, text}, conn), do: patch(conn, &announce/1, text: text)
  defp apply_patch(:clear_text, conn), do: patch_signals(conn, %{wanted: ""})

  defp resync(conn, reading) do
    {:ok, reading} = Reading.load(reading.id, reading.reader_id)

    [{:nib, reading, nil}, {:dialogs, reading}, :clear_text]
    |> Enum.reduce(conn, &apply_patch/2)
  end

  # -- components ----------------------------------------------------------------

  attr :reading, :map, required: true
  attr :focus, :atom, default: nil, doc: "after a patch: :article, :first_link, or nil"

  @doc "The whole Nib, patched as one element."
  def nib(assigns) do
    reading = assigns.reading
    view = Reading.view(reading)
    mode = reading.inquest != :none and reading.inquest != :asking

    assigns =
      assign(assigns,
        view: view,
        mode: mode,
        offer_inquest: reading.budget > 0 and not mode and not view.done,
        remaining: Reading.remaining(reading)
      )

    ~H"""
    <article
      id="nib"
      tabindex="-1"
      aria-labelledby="nib-title"
      data-nib={@view.nib}
      data-mode={@mode && "inquest"}
      data-init={focus(@focus)}
      data-on:keydown__window={@mode && escape_leaves()}
    >
      <h1 id="nib-title">{@view.title}</h1>
      <.ink sections={@view.ink} />

      <p :if={@mode} role="note">
        <b>Inquest mode.</b>
        Point at a Link, or move to it with Tab, to see whether another path hides behind it.
        <button type="button" data-on:click={event("leave")}>Leave Inquest mode</button>
      </p>

      <nav :if={@view.links != []} aria-label="Links">
        <ul>
          <.link_item
            :for={{link, i} <- Enum.with_index(@view.links)}
            link={link}
            index={i}
            mode={@mode}
            state={:default}
          />
        </ul>
      </nav>

      <p :if={@offer_inquest} data-inquest>
        <button type="button" data-on:click={event("inquest")}>Inquest</button>
        <small>{inquests(@remaining)} left</small>
      </p>

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

  attr :link, :map, required: true
  attr :index, :integer, required: true
  attr :mode, :boolean, required: true
  attr :state, :any, required: true, doc: ":default, :plain, or {:fork, fork}"

  @doc """
  One Link. Outside Inquest mode it takes the Link. In Inquest mode it flips:
  on mouse hover or keyboard focus (`look`), or on a first tap; a click or
  Enter on a flipped Link takes the fork. Touch and mouse focus do not count
  as looking, so a tap is a tap.
  """
  def link_item(%{mode: false} = assigns) do
    ~H"""
    <li id={"link-#{@index}"}>
      <button type="button" data-on:click={event("take:" <> @link.id)}>
        <.parts parts={@link.label} />
      </button>
    </li>
    """
  end

  def link_item(%{state: {:fork, fork}} = assigns) do
    assigns = assign(assigns, fork: fork)

    ~H"""
    <li id={"link-#{@index}"} data-flipped>
      <button
        type="button"
        data-on:click={event("take-fork:" <> @fork.id)}
        data-on:pointerleave={"evt.pointerType === 'mouse' && " <> event("unlook:" <> @link.id)}
        data-on:blur={event("unlook:" <> @link.id)}
      >
        <.parts parts={@fork.label} />
        <small>instead of “<.parts parts={@link.label} />”</small>
      </button>
    </li>
    """
  end

  def link_item(assigns) do
    ~H"""
    <li id={"link-#{@index}"} data-plain={@state == :plain}>
      <button
        type="button"
        data-on:click={event("tap:" <> @link.id)}
        data-on:pointerenter={
          @state == :default && "evt.pointerType === 'mouse' && " <> event("look:" <> @link.id)
        }
        data-on:focus={
          @state == :default && "el.matches(':focus-visible') && " <> event("look:" <> @link.id)
        }
      >
        <.parts parts={@link.label} />
        <small :if={@state == :plain}>no other path here</small>
      </button>
    </li>
    """
  end

  attr :text, :string, required: true

  @doc "The one live region: polite, outside the Nib, so it survives patches."
  def announce(assigns) do
    ~H"""
    <p id="announce" role="status">{@text}</p>
    """
  end

  attr :reading, :map, required: true

  @doc "The Inquest boxes, when one is open: modal, so focus stays inside."
  def dialogs(%{reading: %Reading{inquest: :asking}} = assigns) do
    ~H"""
    <div id="dialogs">
      <.box
        title="What would you change here?"
        hint="Tell the Inker what you would want to happen. Nothing is spent unless you take another path."
        answer="inquest-answer"
        skip="inquest-skip"
      />
    </div>
    """
  end

  def dialogs(%{reading: %Reading{inquest: {:wanting, canon}}} = assigns) do
    label = Enum.find(Reading.view(assigns.reading).links, &(&1.id == canon)).label
    assigns = assign(assigns, label: Reading.plain(label))

    ~H"""
    <div id="dialogs">
      <.box
        title={"What did you want instead of “#{@label}”?"}
        hint="The Inker will read this. Then choose a Link as usual."
        answer="wanted-answer"
        skip="wanted-skip"
      />
    </div>
    """
  end

  def dialogs(assigns) do
    ~H"""
    <div id="dialogs"></div>
    """
  end

  attr :title, :string, required: true
  attr :hint, :string, required: true
  attr :answer, :string, required: true
  attr :skip, :string, required: true

  defp box(assigns) do
    ~H"""
    <dialog
      id="box"
      aria-labelledby="box-title"
      aria-describedby="box-hint"
      data-init="el.showModal()"
      data-on:cancel__prevent={event(@skip)}
    >
      <form data-on:submit__prevent={event(@answer)}>
        <h2 id="box-title">{@title}</h2>
        <p id="box-hint">{@hint}</p>
        <textarea aria-labelledby="box-title" data-bind:wanted rows="5" maxlength="2000"></textarea>
        <p>
          <button type="submit">Submit</button>
          <button type="button" data-on:click={event(@skip)}>Skip</button>
        </p>
      </form>
    </dialog>
    """
  end

  # After a patch, where focus goes: the new Nib (and to its top), or its
  # first Link (after a box closes, or when Inquest mode starts or ends).
  defp focus(:article), do: "el.focus({preventScroll: true}); el.scrollIntoView({block: 'start'})"

  defp focus(:first_link),
    do: "(el.querySelector('nav[aria-label=Links] button') || el).focus({preventScroll: true})"

  defp focus(_), do: nil

  defp escape_leaves,
    do: "evt.key === 'Escape' && !document.querySelector('dialog[open]') && " <> event("leave")

  defp not_found(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(404, "Not Found")
    |> Plug.Conn.halt()
  end
end
