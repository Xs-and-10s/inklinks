defmodule Inklinks.Events.Catalog do
  @moduledoc """
  Every event a reading can record: its type, where it came from, and the
  keys its `data` holds. The one source of truth; docs/events.md carries
  the same table (`markdown/0`), and a test fails if the two drift apart.

  **Origins.** Every event says where it came from:

    * `linker`: a Linker's own action (a choice, an answer, a look). Only
      the Linker knows it; nothing can rebuild it.
    * `engine`: what the engine computed from the story, the seed and the
      choices so far (the Nib shown, an ending). Replay rebuilds it
      exactly, and a test checks that it does.
    * `platform`: what the platform decided or inferred, by its own rules
      or the clock (asking for a rating, turning an Inquest down, a
      reading abandoned). It changes if those rules change.

  (Not `actor`: in cohort play that would read as the character who
  acted.)

  Time per Nib, for one, runs from `nib_shown` to the next `linker` event:
  events the engine or platform write in the same moment are not the
  Linker's time.

  `Inklinks.Reading.record/2` checks every event against this catalogue
  and stamps its origin, so the log can only hold what is listed here.
  """

  @type origin :: :linker | :engine | :platform

  @type entry :: %{
          type: String.t(),
          origin: origin(),
          required: [String.t()],
          optional: [String.t()],
          milestone: 2 | 3 | 4,
          about: String.t()
        }

  # Forks asked for from an earlier Nib carry `at` and `back_to`.
  @where ~w(at back_to)

  @entries [
    # -- reading ---------------------------------------------------------------
    %{
      type: "reading_started",
      origin: :linker,
      required: ~w(seed ir ir_sha256 engine inquests),
      optional: [],
      milestone: 2,
      about: "A Linker begins a reading."
    },
    %{
      type: "returned_for_another_ending",
      origin: :platform,
      required: ~w(readings_finished endings_seen),
      optional: [],
      milestone: 4,
      about: "The reading is by a Linker who has finished this Inklink before."
    },
    %{
      type: "nib_shown",
      origin: :engine,
      required: ~w(nib passed links visit),
      optional: [],
      milestone: 2,
      about: "A Nib is put in front of the Linker. `visit` > 1 is a re-read."
    },
    %{
      type: "link_taken",
      origin: :linker,
      required: ~w(link nib label),
      optional: [],
      milestone: 2,
      about: "The Linker takes an offered Link."
    },
    %{
      type: "ending_reached",
      origin: :engine,
      required: ~w(ending),
      optional: [],
      milestone: 2,
      about: "A `finale` Nib is shown."
    },
    %{
      type: "reading_finished",
      origin: :engine,
      required: ~w(ending),
      optional: [],
      milestone: 2,
      about: "A Nib with no Links is shown: nothing left to choose."
    },
    # -- Inquests ----------------------------------------------------------------
    %{
      type: "inquest_opened",
      origin: :linker,
      required: ~w(nib remaining),
      optional: [],
      milestone: 3,
      about: "The Linker presses Inquest; the box opens."
    },
    %{
      type: "inquest_submitted",
      origin: :linker,
      required: ~w(nib text),
      optional: [],
      milestone: 3,
      about: "They say what they would change here."
    },
    %{
      type: "inquest_skipped",
      origin: :linker,
      required: ~w(nib),
      optional: [],
      milestone: 3,
      about: "They skip the box (Skip, Escape, or nothing written)."
    },
    %{
      type: "inquest_turned_down",
      origin: :platform,
      required: ~w(nib reason),
      optional: [],
      milestone: 3,
      about: "Nothing to look at: noted, nothing spent. `reason`: `no_forks` or `none_left`."
    },
    %{
      type: "inquest_mode_entered",
      origin: :platform,
      required: ~w(nib remaining),
      optional: [],
      milestone: 3,
      about: "Forks are hidden here, or asked for from here: Inquest mode."
    },
    %{
      type: "fork_looked",
      origin: :linker,
      required: ~w(nib link fork label),
      optional: @where,
      milestone: 3,
      about:
        "A fork is shown, the first time in this Inquest mode (one per fork in an opened group)."
    },
    %{
      type: "fork_taken",
      origin: :linker,
      required: ~w(nib link fork label),
      optional: @where,
      milestone: 3,
      about: "The Linker takes a fork they were shown. The only event that spends an Inquest."
    },
    %{
      type: "fork_declined",
      origin: :platform,
      required: ~w(nib link fork by),
      optional: @where,
      milestone: 3,
      about:
        "A fork shown, left untaken when Inquest mode ends. `by`: `left`, `wanted_instead`, `took_link`, `took_another_fork`."
    },
    %{
      type: "wanted_instead_opened",
      origin: :linker,
      required: ~w(nib link),
      optional: @where,
      milestone: 3,
      about: "In Inquest mode, they choose an offered Link with no fork."
    },
    %{
      type: "wanted_instead_submitted",
      origin: :linker,
      required: ~w(nib link text),
      optional: @where,
      milestone: 3,
      about: "They say what they wanted instead."
    },
    %{
      type: "wanted_instead_skipped",
      origin: :linker,
      required: ~w(nib link),
      optional: @where,
      milestone: 3,
      about: "They skip that."
    },
    %{
      type: "inquest_mode_left",
      origin: :linker,
      required: ~w(nib reason),
      optional: [],
      milestone: 3,
      about:
        "Inquest mode ends without a fork taken. `reason`: `left`, `wanted_instead`, `took_link`."
    },
    # -- ratings, stopping, returning ------------------------------------------
    %{
      type: "rating_asked",
      origin: :platform,
      required: ~w(ending path),
      optional: [],
      milestone: 4,
      about: "A finale, not yet asked this reading, and not rated before by this Linker."
    },
    %{
      type: "change_wished",
      origin: :linker,
      required: ~w(nib back_to chose text),
      optional: [],
      milestone: 4,
      about: "Under More…, a moment they would change (Add another, or Done)."
    },
    %{
      type: "nothing_to_change",
      origin: :linker,
      required: ~w(ending),
      optional: [],
      milestone: 4,
      about: "They opened More… and left “I wouldn’t change a thing” selected."
    },
    %{
      type: "rating_given",
      origin: :linker,
      required: ~w(ending ending_score inklink_score),
      optional: ~w(path_score),
      milestone: 4,
      about: "They answer the box. Scores 1 to 5, or null."
    },
    %{
      type: "rating_dismissed",
      origin: :linker,
      required: ~w(ending),
      optional: [],
      milestone: 4,
      about: "Not now, Escape, or an empty answer."
    },
    %{
      type: "reading_abandoned",
      origin: :platform,
      required: ~w(nib idle_seconds),
      optional: [],
      milestone: 4,
      about: "Inferred: unfinished and idle. `occurred_at` is when they stopped."
    },
    %{
      type: "reading_resumed",
      origin: :platform,
      required: ~w(nib after_seconds),
      optional: [],
      milestone: 4,
      about: "They act again in a reading inferred abandoned; written before their action."
    }
  ]

  @by_type Map.new(@entries, &{&1.type, &1})

  @doc "Every entry, in the order they are documented."
  @spec all() :: [entry()]
  def all, do: @entries

  @doc "The entry for a type, or `nil`."
  @spec fetch(String.t()) :: entry() | nil
  def fetch(type), do: Map.get(@by_type, type)

  @doc """
  Checks an event against the catalogue and stamps its origin. Raises on an
  unknown type, a missing key or an unexpected one: that is a bug in the
  platform, never the Linker's doing.
  """
  @spec stamp!(map()) :: map()
  def stamp!(%{type: type} = event) do
    entry = fetch(type) || raise ArgumentError, "unknown event type #{inspect(type)}"
    keys = event |> Map.get(:data, %{}) |> Map.keys()

    missing = entry.required -- keys
    extra = keys -- (entry.required ++ entry.optional)

    if missing != [] or extra != [] do
      raise ArgumentError,
            "#{type}: missing #{inspect(missing)}, unexpected #{inspect(extra)}"
    end

    Map.put(event, :origin, Atom.to_string(entry.origin))
  end

  @doc "The catalogue as the Markdown table in docs/events.md."
  @spec markdown() :: String.t()
  def markdown do
    rows =
      for e <- @entries do
        keys =
          Enum.map(e.required, &"`#{&1}`") ++ Enum.map(e.optional, &"`#{&1}`?")

        "| `#{e.type}` | #{e.origin} | #{Enum.join(keys, ", ")} | #{e.about} |"
      end

    Enum.join(
      ["| Type | Origin | `data` (`?`: optional) | When |", "|---|---|---|---|" | rows],
      "\n"
    )
  end
end
