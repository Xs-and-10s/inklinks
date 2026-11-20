defmodule InklinksWeb.ReadingPage do
  @moduledoc """
  The reader: one Nib at a time, its offered Links, and Inquests (flow D).

  `GET /readings/:id` renders the page. Everything else is a Datastar event,
  `POST /readings/:id/_event/<name>`, answered with SSE patches:

  | Event | Does |
  |---|---|
  | `take:<link>` | takes an offered Link; the next Nib replaces `#nib` in a View Transition |
  | `inquest` | opens the box: "What would you change here?" |
  | `inquest-answer`, `inquest-skip` | answers it: noted, or Inquest mode |
  | `look:<at>:<link>`, `unlook:<at>:<link>` | opens an offered Link into its group of forks, and closes it (pointer or keyboard focus) |
  | `tap:<at>:<link>` | a click or tap in Inquest mode: opens the group, or asks what they wanted instead |
  | `take-fork:<fork>` | takes a fork from an open group; spends one Inquest |
  | `wanted-answer`, `wanted-skip` | answers "what did you want instead", then leaves Inquest mode |
  | `leave` | leaves Inquest mode (also Escape) |
  | `rate`, `rating-dismiss` | answers the ratings box after a finale, or puts it off |

  `<at>` is `here` for the current Nib, or the version of an earlier visit
  whose forks may be asked for from here (`Reading.places/1`); the page
  shows those as "Back when you chose …".

  One group is open at a time: opening one closes any other. Forks are
  never in the page until a Linker opens a group: the server renders offered
  Links only, and the forks' labels arrive in the patch that answers the
  flip. Announcements go to one `role=status` region outside the Nib, so it
  survives every patch.

  A reading belongs to its reader. `mount/2` checks on GET and `authorize/2`
  before every event, because dstar runs them on separate routes.
  """
  use Dstar.Page

  import InklinksWeb.Ink

  alias Inklinks.{Engine, Inquest, Rating, Reading}
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
      {:ok, [{:dialogs, reading}, {:nib, reading, :article}, {:announce, ""}]}
    end
  end

  defp run("inquest", reading, _) do
    with {:ok, reading} <- Inquest.open(reading), do: {:ok, [{:dialogs, reading}]}
  end

  defp run("inquest-answer", reading, signals), do: answer(reading, signals["wanted"])
  defp run("inquest-skip", reading, _), do: answer(reading, nil)

  defp run("look:" <> target, reading, _) do
    with {:ok, at, link} <- target(target),
         {:ok, reading, found} <- Inquest.look(reading, link, at) do
      {:ok, opened(reading, at, link, found)}
    end
  end

  defp run("unlook:" <> target, %Reading{inquest: :mode} = reading, _) do
    with {:ok, at, link} <- target(target) do
      {:ok, [{:links, reading, {at, link, :closed}}, {:announce, ""}]}
    end
  end

  defp run("tap:" <> target, reading, _) do
    with {:ok, at, link} <- target(target) do
      case Inquest.want(reading, link, at) do
        {:ok, reading, :asked} -> {:ok, [{:dialogs, reading}]}
        {:ok, reading, found} -> {:ok, opened(reading, at, link, found)}
        error -> error
      end
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

  defp run("rate", reading, signals) do
    with {:ok, reading} <- Rating.answer(reading, answers(signals)) do
      said = if reading.rating == :done, do: "Thank you. The Inker will read this.", else: ""
      {:ok, [:close_dialogs, :clear_rating, {:nib, reading, nil}, {:announce, said}]}
    end
  end

  # "Add another": save this moment, strike it from the list, and go back to
  # "I wouldn't change a thing". Only the list and its status are patched:
  # the scores already chosen stay in their signals, and the dialog stays
  # open (a morph of the dialog itself would drop its `open`).
  defp run("wish", reading, signals) do
    with {:ok, reading} <- Rating.wish(reading, answers(signals)) do
      {:ok,
       [{:moments, reading}, :clear_moment, {:box_status, "Saved. Pick another, or press Done."}]}
    end
  end

  defp run("rating-dismiss", reading, _) do
    with {:ok, reading} <- Rating.dismiss(reading) do
      {:ok, [:close_dialogs, :clear_rating, {:nib, reading, nil}, {:announce, ""}]}
    end
  end

  defp run(_event, _reading, _), do: {:error, :unknown_event}

  defp answers(signals) do
    %{
      "ending" => signals["ratingEnding"],
      "inklink" => signals["ratingInklink"],
      "path" => signals["ratingPath"],
      "change_at" => signals["changeAt"],
      "change_text" => signals["changeText"],
      "more_opened" => signals["moreOpened"]
    }
  end

  # `here:obey_at_thornbury` or `2:obey_at_thornbury`. A Link id may itself
  # hold colons, so only the first one splits.
  defp target(target) do
    case String.split(target, ":", parts: 2) do
      ["here", link] ->
        {:ok, nil, link}

      [version, link] ->
        with {v, ""} <- Integer.parse(version),
             do: {:ok, v, link},
             else: (_ -> {:error, :bad_target})

      _ ->
        {:error, :bad_target}
    end
  end

  defp answer(reading, text) do
    with {:ok, reading, outcome} <- Inquest.answer(reading, text) do
      said =
        case outcome do
          :noted ->
            "Noted. The Inker will read this."

          :inquest_mode ->
            "Inquest mode. Point at a Link, or move to it with Tab, to see whether other " <>
              "paths hide behind it. Escape leaves Inquest mode."
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

  # Opening one group closes every other.
  defp opened(reading, at, link, {:forks, forks}) do
    count = if length(forks) == 1, do: "Another path", else: "#{length(forks)} other paths"
    names = Enum.map_join(forks, "; ", &Reading.plain(&1.label))

    said =
      "#{back_when(reading, at)}#{count}: #{names}. Take one to spend one Inquest " <>
        "(#{inquests(Reading.remaining(reading))} left)."

    [{:links, reading, {at, link, {:forks, forks}}}, {:announce, said}]
  end

  # No announcement: the Link says so itself, in its own label, so a quick
  # Tab across several Links cannot leave a stale message behind.
  defp opened(reading, at, link, :no_forks), do: [{:links, reading, {at, link, :no_forks}}]

  defp back_when(_reading, nil), do: ""

  defp back_when(reading, at) do
    case Enum.find(Reading.places(reading), &(&1.at == at)) do
      %{chose: chose} when is_binary(chose) -> "Back when you chose #{Reading.quoted(chose)}: "
      _ -> "Earlier: "
    end
  end

  defp choices(1), do: "1 choice"
  defp choices(n), do: "#{n} choices"

  defp inquests(1), do: "1 Inquest"
  defp inquests(n), do: "#{n} Inquests"

  # -- patches -------------------------------------------------------------------

  defp apply_patch({:nib, reading, focus}, conn) do
    patch(conn, &nib/1, [reading: reading, focus: focus],
      mode: :replace,
      use_view_transitions: true
    )
  end

  # Every offered Link in every place, re-rendered: the one named in its new
  # state, all others closed. That is how opening one group closes another.
  defp apply_patch({:links, reading, {at, link, state}}, conn) do
    for place <- places(reading),
        {offered, i} <- Enum.with_index(place.links),
        reduce: conn do
      conn ->
        mine = place.at == at and offered.id == link
        state = if mine, do: state, else: :closed

        # Only the Link that changed animates.
        patch(
          conn,
          &link_item/1,
          [link: offered, index: i, at: place.at, mode: true, state: state],
          use_view_transitions: mine
        )
    end
  end

  defp apply_patch({:dialogs, reading}, conn), do: patch(conn, &dialogs/1, reading: reading)
  defp apply_patch(:close_dialogs, conn), do: patch(conn, &dialogs/1, reading: nil)
  defp apply_patch({:announce, text}, conn), do: patch(conn, &announce/1, text: text)
  defp apply_patch(:clear_text, conn), do: patch_signals(conn, %{wanted: ""})

  defp apply_patch(:clear_rating, conn) do
    patch_signals(conn, %{
      ratingEnding: "",
      ratingInklink: "",
      ratingPath: "",
      changeAt: "none",
      changeText: "",
      moreOpened: false
    })
  end

  defp apply_patch(:clear_moment, conn),
    do: patch_signals(conn, %{changeAt: "none", changeText: ""})

  defp apply_patch({:moments, reading}, conn),
    do: patch(conn, &moments/1, moments: Rating.moments(reading))

  defp apply_patch({:box_status, text}, conn), do: patch(conn, &box_status/1, text: text)

  defp resync(conn, reading) do
    {:ok, reading} = Reading.load(reading.id, reading.reader_id)
    Enum.reduce([{:nib, reading, nil}, {:dialogs, reading}, :clear_text], conn, &apply_patch/2)
  end

  # The places an Inquest looks, each with its offered Links as the Linker
  # saw them there.
  defp places(reading) do
    for place <- Reading.places(reading) do
      view = Engine.call(:view, [reading.loaded.story, place.state])
      Map.put(place, :links, view.links)
    end
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
        earlier: if(mode, do: reading |> places() |> tl(), else: []),
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
        Point at a Link, or move to it with Tab, to see whether other paths hide behind it.
        <button type="button" data-on:click={event("leave")}>Leave Inquest mode</button>
      </p>

      <nav :if={@view.links != []} aria-label="Links">
        <ul>
          <.link_item
            :for={{link, i} <- Enum.with_index(@view.links)}
            link={link}
            index={i}
            at={nil}
            mode={@mode}
            state={:closed}
          />
        </ul>
      </nav>

      <nav :for={place <- @earlier} aria-labelledby={"earlier-#{place.at}"} data-earlier>
        <h2 id={"earlier-#{place.at}"}>
          <%= if place.chose do %>
            Back when you chose <span data-chosen>{place.chose}</span>
          <% else %>
            Earlier
          <% end %>
          <small>(undoes {choices(place.back)})</small>
        </h2>
        <ul>
          <.link_item
            :for={{link, i} <- Enum.with_index(place.links)}
            link={link}
            index={i}
            at={place.at}
            mode={true}
            state={:closed}
          />
        </ul>
      </nav>

      <p :if={@offer_inquest} data-inquest>
        <button type="button" data-on:click={event("inquest")}>Inquest</button>
        <small>{inquests(@remaining)} left</small>
      </p>

      <p
        :if={@reading.rating == :asking}
        data-rating-due
        data-on-intersect__once="setTimeout(() => document.getElementById('box')?.showModal(), 4000)"
      >
      </p>

      <footer :if={@view.done}>
        <p>The end.</p>
        <form method="post" action={"/inklinks/#{@reading.inklink_id}/readings"}>
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="again" value="true" />
          <button>Read again</button>
        </form>
        <button
          :if={@reading.rating == :asking}
          type="button"
          data-on:click="document.getElementById('box')?.showModal()"
        >
          Rate this ending
        </button>
        <a href={"/readings/#{@reading.id}/path"}>Your path</a>
        <a href="/">Back to the library</a>
      </footer>
    </article>
    """
  end

  attr :link, :map, required: true
  attr :index, :integer, required: true
  attr :at, :any, required: true, doc: "nil for the current Nib, or an earlier visit's version"
  attr :mode, :boolean, required: true
  attr :state, :any, required: true, doc: ":closed, :no_forks, or {:forks, forks}"

  @doc """
  One offered Link. Outside Inquest mode it takes the Link. In Inquest mode
  it opens into the group of forks that stand in for it, in the Inker's
  order: on mouse hover or keyboard focus (`look`), or on a first tap. The
  group stays open while the pointer or focus is inside it; each fork is a
  button that takes it. Touch and mouse focus do not count as looking, so a
  tap is a tap.

  The open group's first fork button takes the place of the Link's own
  button, so a morph keeps keyboard focus where it was.
  """
  def link_item(%{mode: false} = assigns) do
    ~H"""
    <li id={"link-here-#{@index}"}>
      <button type="button" data-on:click={event("take:" <> @link.id)}>
        <.parts parts={@link.label} />
      </button>
    </li>
    """
  end

  def link_item(%{state: {:forks, forks}} = assigns) do
    assigns = assign(assigns, forks: forks, target: target_of(assigns))

    ~H"""
    <li
      id={"link-#{place_key(@at)}-#{@index}"}
      data-open
      data-on:pointerleave={"evt.pointerType === 'mouse' && " <> event("unlook:" <> @target)}
      data-on:focusout={"!el.contains(evt.relatedTarget) && " <> event("unlook:" <> @target)}
    >
      <button :for={fork <- @forks} type="button" data-on:click={event("take-fork:" <> fork.id)}>
        <.parts parts={fork.label} />
      </button>
      <small>instead of {@link.label |> Reading.plain() |> Reading.quoted()}</small>
    </li>
    """
  end

  def link_item(assigns) do
    assigns = assign(assigns, target: target_of(assigns))

    ~H"""
    <li id={"link-#{place_key(@at)}-#{@index}"}>
      <button
        type="button"
        data-on:click={event("tap:" <> @target)}
        data-on:pointerenter={
          @state == :closed && "evt.pointerType === 'mouse' && " <> event("look:" <> @target)
        }
        data-on:focus={
          @state == :closed && "el.matches(':focus-visible') && " <> event("look:" <> @target)
        }
      >
        <.parts parts={@link.label} />
        <small :if={@state == :no_forks}>no other path here</small>
      </button>
    </li>
    """
  end

  defp target_of(assigns), do: "#{place_key(assigns.at)}:#{assigns.link.id}"

  defp place_key(nil), do: "here"
  defp place_key(version), do: Integer.to_string(version)

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

  def dialogs(%{reading: %Reading{inquest: {:wanting, link, at}} = reading} = assigns) do
    place = Enum.find(places(reading), &(&1.at == at))
    label = place && Enum.find(place.links, &(&1.id == link))
    assigns = assign(assigns, label: if(label, do: Reading.plain(label.label), else: link))

    ~H"""
    <div id="dialogs">
      <.box
        title={"What did you want instead of #{Reading.quoted(@label)}?"}
        hint="The Inker will read this. Then choose a Link as usual."
        answer="wanted-answer"
        skip="wanted-skip"
      />
    </div>
    """
  end

  # The ratings box is rendered closed. It opens a few seconds after the end
  # of the finale (`data-rating-due`) scrolls into view, so it never covers
  # the ending before it is read, or at once from "Rate this ending".
  def dialogs(%{reading: %Reading{rating: :asking} = reading} = assigns) do
    assigns = assign(assigns, path: reading.forked, moments: Rating.moments(reading))

    ~H"""
    <div id="dialogs">
      <dialog
        id="box"
        aria-labelledby="box-title"
        aria-describedby="box-hint"
        data-signals__ifmissing="{ratingEnding: '', ratingInklink: '', ratingPath: '', changeAt: 'none', changeText: '', moreOpened: false}"
        data-on:cancel__prevent={event("rating-dismiss")}
      >
        <form data-on:submit__prevent={event("rate")}>
          <h2 id="box-title">How was it?</h2>
          <p id="box-hint">All optional. 1 is “not for me”, 5 is “loved it”.</p>

          <.scale name="ending" signal="rating-ending" legend="The ending" />
          <.scale name="inklink" signal="rating-inklink" legend="The Inklink overall" />
          <.scale :if={@path} name="path" signal="rating-path" legend="Your path, off the canon" />

          <details :if={@moments != []} data-on:toggle="$moreOpened = $moreOpened || el.open">
            <summary>More…</summary>
            <.moments moments={@moments} />
            <label>
              What would you change? <textarea data-bind:change-text rows="3" maxlength="2000"></textarea>
            </label>
            <p>
              <button
                type="button"
                data-attr:disabled="$changeAt == 'none'"
                data-on:click={event("wish")}
              >
                Add another
              </button>
            </p>
          </details>

          <p id="box-status" role="status"></p>

          <p>
            <button type="submit">Done</button>
            <button type="button" data-on:click={event("rating-dismiss")}>Not now</button>
          </p>
        </form>
      </dialog>
    </div>
    """
  end

  def dialogs(assigns) do
    ~H"""
    <div id="dialogs"></div>
    """
  end

  attr :text, :string, required: true

  # The box's own status line: a live region inside the modal, where a
  # screen reader is listening while the box is open.
  defp box_status(assigns) do
    ~H"""
    <p id="box-status" role="status">{@text}</p>
    """
  end

  attr :moments, :list, required: true

  # The moments a Linker could change, oldest first. Each choice sits on its
  # own line, in the reading face, as the Link read: no quotes added (a line
  # of dialogue brings its own). A moment already saved is struck and
  # disabled. The whole label is the radio's, so tapping either line picks it.
  defp moments(assigns) do
    ~H"""
    <fieldset id="moments">
      <legend>A moment you would change</legend>
      <label>
        <input type="radio" name="change" value="none" data-bind:change-at />
        <span>I wouldn’t change a thing</span>
      </label>
      <label :for={moment <- @moments} data-wished={moment.wished}>
        <input
          type="radio"
          name="change"
          value={moment.at}
          disabled={moment.wished}
          data-bind:change-at
        />
        <span>Where you chose</span>
        <span data-chosen>
          <%= if moment.wished do %>
            <s>{moment.chose}</s>
          <% else %>
            {moment.chose}
          <% end %>
        </span>
      </label>
    </fieldset>
    """
  end

  attr :name, :string, required: true
  attr :signal, :string, required: true
  attr :legend, :string, required: true

  # One rating: five radio buttons in a fieldset, so arrow keys move along
  # the scale and a screen reader hears "The ending, 3 of 5".
  defp scale(assigns) do
    ~H"""
    <fieldset data-scale>
      <legend>{@legend}</legend>
      <label :for={n <- 1..5}>
        <input type="radio" name={@name} value={n} {%{"data-bind:#{@signal}" => true}} />
        <span>{n}</span>
      </label>
    </fieldset>
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
