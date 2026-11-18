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
    * **Forks never leave the engine unasked.** `view/2` shows canon Links
      only. A fork crosses the boundary only through `fork/3`, one at a time,
      when a Linker in Inquest mode flips the canon Link it stands in for.
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
          | %{type: :speech, who: String.t(), name: String.t(), paragraphs: [paragraph()]}
          | %{type: :beat, time: String.t() | nil}

  @typedoc "A Link as the Linker sees it."
  @type link :: %{id: link_id(), label: paragraph()}

  @typedoc "What to show now."
  @type view :: %{
          nib: passage(),
          ink: [block()],
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

  @doc "What the Linker sees now: the Nib's Ink and its canon Links."
  @callback view(story(), state()) :: view()

  @doc "Takes a canon Link. Only a Link that `view/2` offers is accepted."
  @callback take(story(), state(), link_id()) :: {:ok, state()} | {:error, :not_offered}

  @doc """
  Whether the current Nib hides any fork the Linker could take now. This is
  all an Inquest learns before the Linker looks: yes (Inquest mode) or no
  ("Noted. The Inker will read this.").
  """
  @callback forks?(story(), state()) :: boolean()

  @doc """
  The fork that stands in for this canon Link, if the Inker hid one here.
  Called once per flip, never in advance.
  """
  @callback fork(story(), state(), canon :: link_id()) :: {:ok, link()} | :none

  @doc "Takes a fork, as `take/3` takes a canon Link."
  @callback take_fork(story(), state(), fork :: link_id()) ::
              {:ok, state()} | {:error, :not_offered}

  @doc "The engine the platform is configured to use."
  @spec impl() :: module()
  def impl, do: Application.get_env(:inklinks, :engine, Inklinks.Engine.Stub)
end
