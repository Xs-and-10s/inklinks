# How the platform calls the engine

The bridge to the Rust interpreter is undecided: a Rustler NIF (which must
not block the BEAM's schedulers) or a port or sidecar service. WASM in the
browser is ruled out, because it would put the forks in the client. These
notes record what the platform actually asks of an engine, how often, with
what, and what it needs back. They decide the bridge.

The contract is `Inklinks.Engine` (`lib/inklinks/engine.ex`). Every call
goes through `Inklinks.Engine.call/2`, which wraps it in a telemetry span
(`[:inklinks, :engine, callback]`), so the counts below are measured, not
guessed. Status: measured on the stub with Ex 3 (milestone 2); Inquest
calls counted on the Littlejon fixture (milestone 3).

## The callbacks

| Call | In | Out |
|---|---|---|
| `load/1` | the IR file's bytes | a story handle, or `{:unsupported, reasons}` |
| `meta/1` | story | title, kind, mode, Inquest budget |
| `start/2` | story, seed | state |
| `view/2` | story, state | the Nib's Ink by passage, its canon Links, ending, done |
| `take/3` | story, state, Link id | state, or `:not_offered` |
| `forks?/2` | story, state | yes or no: is any fork hidden behind a Link on offer? |
| `fork/3` | story, state, canon Link id | the fork that stands in for it (id and label), or none |
| `take_fork/3` | story, state, fork id | state, or `:not_offered` |

## When the platform calls, per request

A reading's state is not kept between requests. Each request rebuilds it
from the log (`Inklinks.Reading.load/2`): `start` with the recorded seed,
then `take` for each `link_taken`.

| Request | Engine calls | |
|---|---|---|
| First listing of an Inklink, or after its file changes | `load` ×1 | cached in ETS by file, mtime and size |
| Start a reading | `start` ×1, `view` ×1, `meta` ×1 | |
| Open a reading (`GET /readings/:id`), *n* Links in | `start` ×1, `take` ×*n*, `view` ×1 | the rebuild |
| Take a Link, *n* Links in | `start` ×1, `take` ×*n* (rebuild), then `take` ×1 and `view` ×3 | the rebuild runs in `authorize/2` before the event |

Inquests (milestone 3) add, on top of the rebuild every event pays
(`start` ×1, then `take` or `take_fork` ×*n*):

| Request | Engine calls |
|---|---|
| Press Inquest | `view` ×1 |
| Answer or skip the box | `view` ×2, `forks?` ×1 |
| Flip a Link (hover, focus or first tap) | `view` ×2, `fork` ×1: **one fork crosses, for one flip** |
| Take a fork | `view` ×2, `fork` ×1, `take_fork` ×1 |
| Leave Inquest mode, or answer "what did you want instead" | `view` ×1–2 |

A flip is the only call made on hover, so it is the one that must be fast:
a reader moving the mouse down a list of Links makes one request per Link.
The stub answers `fork` in microseconds.

So **one Link costs *n* + 1 `take`s**, and a whole reading of *n* Links
costs about *n*²/2. For a story that is nothing; for a game with thousands
of moves it is the first thing to fix.

## Measured (stub, Ex 3, dev machine)

| What | Time |
|---|---|
| `load` (82 KB of IR: JSON decode and checks) | 3.3 ms, once |
| `start` | 0.15 ms (5 ms on the very first call: code loading) |
| `take` | 0.12–0.19 ms |
| `view` | 2 µs (the stub renders on arrival and keeps the view) |
| Rebuilding a finished reading (9 Links), engine only | ≈ 1.1 ms |
| The same, with the event query, in dev with debug logging | ≈ 12 ms |
| State size (`:erlang.external_size`) | 2.4 KB |

## What this says about the bridge

- **Calls are small and frequent, not large and rare.** A rebuild is
  1 + *n* calls in a row with the same story handle. Over a NIF that is
  cheap (each call is microseconds, well under the 1 ms a NIF may hold a
  scheduler, so no dirty scheduler is needed for `take` and `view`; `load`
  parses a whole IR file and should run on a dirty CPU scheduler). Over a
  sidecar it is 1 + *n* round trips per request, which argues for one of:
  - a **`replay(story, seed, [link ids])`** call that rebuilds in one trip;
  - **`snapshot(state)` / `restore(story, bytes)`**, so the platform can
    store a snapshot beside the log and replay only what came after it;
  - keeping each open reading's state **in a process** (a GenServer per
    reading, or the sidecar holding it), so a Link is one `take`.
  Any of these also fixes the *n*² above.
- **Handles must be cheap to pass.** The story is passed on every call. As
  a NIF resource that is a pointer; across a sidecar it must be an id the
  sidecar resolves, never the IR again.
- **Determinism is load-bearing.** The log holds only the seed and the
  Links; everything else is recomputed. The Rust engine's RNG, shuffles
  and rendering must be stable across engine versions for a reading to
  replay, or `reading_started` must record the engine version and the
  platform must keep that version able to play it. `reading_started`
  already records `ir_sha256`, so a reading is replayed against the IR it
  began on, not a revised one (not yet enforced: the platform plays the
  current file).
- **The stub renders on arrival.** Reading `aka` rolls dice, so rendering
  twice would change the story. The Rust interpreter also renders once,
  on arrival; `view` must stay a pure read.

## Decisions so far

- **IR crosses as JSON bytes.** A Rust engine parses it with serde; nothing
  is converted term by term.
- **Handles are opaque.** The platform never looks inside a story or a
  state.
- **The log is the record, not the state.** See above.
- **Forks cross only when asked.** `view/2` returns canon Links only;
  `fork/3` returns one fork, for one flip. `forks?/2` says only yes or no.
  A fork's id reaches the page only in the patch that answers its flip,
  and the platform refuses to take a fork the Linker has not looked at.
- **The platform owns Inquests.** The budget comes from `meta/1`; what is
  left is counted from the log. The engine never spends.
