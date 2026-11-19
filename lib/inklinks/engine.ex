defmodule Inklinks.Engine do
  @moduledoc """
  The boundary between the platform and whatever plays an Inklink.

  For now that is `Inklinks.Engine.Stub`, a small Elixir walker for stories.
  Later it is the Rust interpreter from inkjot-compiler-rust, behind a
  Rustler NIF or a sidecar service. Everything the platform asks of an
  engine goes through these callbacks, and docs/engine-calls.md records how
  often, with what, and what comes back. That record decides the bridge.

  ## The rules of the boundary

    * **IR in, as JSON bytes.** `load/1` takes the file's contents, not a
      decoded map: a Rust engine parses with serde, and nothing has to be
      converted term by term across the boundary.
    * **Opaque handles out.** `story` and `state` are the engine's own. The
      platform never looks inside; it only passes them back.
    * **Deterministic.** The same story, seed and Links taken always give
      the same state. So a reading can be rebuilt from its event log
      (`reading_started` carries the seed; each `link_taken` / `fork_taken`
      a Link id), and the log, not the engine's state, is the record.
    * **Forks never leave the engine unasked.** `view/2` shows the offered
      Links only. Forks cross the boundary only through `forks/4`, for one
      offered Link at a time, when a Linker in Inquest mode flips it.
    * **The platform owns Inquests.** How many a reading has is declared in
      the IR (`resource inquests: 3`); how many are left is counted from the
      log. The engine says where forks are and plays them; it never spends.
  """

  @typedoc "A loaded Inklink: whatever the engine needs to play it."
  @type story :: term()

  @typedoc "One reading's position and world: whatever the engine needs."
  @type state :: term()

  @type link_id :: String.t()
  @type passage :: String.t()

  @typedoc """
  A run of text. A plain string, or styled text that may nest:
  `%{style: [:italic], parts: ["me"]}`. This is the shape requested for
  IR 3 (docs/ir3-requests.md); an engine reading IR 2 lowers asterisks into
  it, so the renderer never parses Inkjot.
  """
  @type part :: String.t() | %{style: [:italic | :bold], parts: [part()]}

  @type paragraph :: [part()]

  @typedoc "A block of Ink, in order."
  @type block ::
          %{type: :prose, paragraphs: [paragraph()]}
          | %{
              type: :speech,
              who: String.t(),
              name: String.t(),
              direction: String.t() | nil,
              paragraphs: [paragraph()]
            }
          | %{type: :beat, time: String.t() | nil}
          | %{
              type: :list,
              items: [%{text: String.t(), mark: String.t() | nil, struck: boolean()}]
            }

  @typedoc """
  One passage's Ink. A step can pass through several passages (a `next:`
  carries straight on), so a view holds one section per passage.
  """
  @type section :: %{passage: passage(), blocks: [block()]}

  @typedoc "A Link as the Linker sees it."
  @type link :: %{id: link_id(), label: paragraph()}

  @typedoc "What to show now. `links` are the offered Links: never a fork."
  @type view :: %{
          title: String.t(),
          # The Nib the Linker is at: the last passage of the step.
          nib: passage(),
          # Passages passed through on the way, by `next:`.
          passed: [passage()],
          ink: [section()],
          links: [link()],
          # The ending this Nib is, when it is a `finale`.
          ending: passage() | nil,
          # True when the Nib offers no Links: the reading is over.
          done: boolean()
        }

  @typedoc "What the platform needs to list an Inklink and set up a reading."
  @type meta :: %{
          title: String.t(),
          kind: String.t() | nil,
          mode: String.t() | nil,
          inquests: non_neg_integer()
        }

  @doc """
  Loads an Inklink from its IR, as JSON bytes. Refuses one this engine cannot
  play, naming what it lacks: `{:error, {:unsupported, ["cohort mode", …]}}`.
  """
  @callback load(ir :: binary()) ::
              {:ok, story()} | {:error, {:unsupported, [String.t()]}} | {:error, term()}

  @doc "Facts about the Inklink, for the library and the Inquest budget."
  @callback meta(story()) :: meta()

  @doc "Begins a reading. The seed drives every roll and shuffle."
  @callback start(story(), seed :: integer()) :: {:ok, state()}

  @doc "What the Linker sees now: the Nib's Ink and its offered Links."
  @callback view(story(), state()) :: view()

  @doc "Takes an offered Link. Only a Link that `view/2` offers is accepted."
  @callback take(story(), state(), link_id()) :: {:ok, state()} | {:error, :not_offered}

  @doc """
  Passages whose forks may be asked for from this Nib (`~ inquest from`),
  besides the Nib's own. Read from the IR; no state needed.
  """
  @callback asked_from(story(), passage()) :: [passage()]

  @doc """
  Whether a state hides any fork the Linker could take, asking from the Nib
  `from`. When the state is at `from`, that is the Nib's own forks; when it
  is an earlier visit (another passage), only the forks marked to be asked
  for from `from`. This is all an Inquest learns before the Linker looks:
  yes (Inquest mode) or no ("Noted. The Inker will read this.").
  """
  @callback forks?(story(), state(), from :: passage()) :: boolean()

  @doc """
  The forks that stand in for this offered Link, in the order the Inker
  wrote them, by the same rule as `forks?/3`. Called once per flip, never in
  advance.
  """
  @callback forks(story(), state(), link :: link_id(), from :: passage()) :: [link()]

  @doc """
  Takes a fork, as `take/3` takes an offered Link. To take a fork asked for
  from a later Nib, the platform passes the state of that earlier visit:
  going back is the platform's replay, not the engine's.
  """
  @callback take_fork(story(), state(), fork :: link_id()) ::
              {:ok, state()} | {:error, :not_offered}

  @doc "The engine the platform is configured to use."
  @spec impl() :: module()
  def impl, do: Application.get_env(:inklinks, :engine, Inklinks.Engine.Stub)

  @doc """
  Calls the configured engine, inside a telemetry span named
  `[:inklinks, :engine, callback]`. Every call the platform makes goes
  through here, so docs/engine-calls.md can count and time them.
  """
  @spec call(atom(), list()) :: term()
  def call(callback, args) do
    :telemetry.span([:inklinks, :engine, callback], %{engine: impl()}, fn ->
      {apply(impl(), callback, args), %{engine: impl()}}
    end)
  end
end
