# How the platform calls the engine

The bridge to the Rust interpreter is undecided: a Rustler NIF (which must
not block the BEAM's schedulers) or a port or sidecar service. WASM in the
browser is ruled out, because it would put the forks in the client. These
notes record what the platform actually asks of an engine, how often, with
what, and what it needs back. They decide the bridge.

The contract is `Inklinks.Engine` (`lib/inklinks/engine.ex`). Status: the
behaviour exists (milestone 1); the stub that implements it, and the
measurements below, come with milestones 2 and 3.

## The callbacks

| Call | When | In | Out |
|---|---|---|---|
| `load/1` | Once per Inklink, cached | the IR file's bytes | a story handle, or what it can't play |
| `meta/1` | Listing; starting a reading | story | title, kind, mode, Inquest budget |
| `start/2` | A reading starts | story, seed | state |
| `view/2` | Every page and every Link | story, state | the Nib's Ink, its canon Links, ending, done |
| `take/3` | Every Link taken | story, state, Link id | state, or `:not_offered` |
| `forks?/2` | An Inquest is submitted or skipped | story, state | yes or no |
| `fork/3` | Every flip in Inquest mode | story, state, canon Link id | the fork, or none |
| `take_fork/3` | A fork taken | story, state, fork id | state, or `:not_offered` |

## Decisions so far

- **IR crosses as JSON bytes.** A Rust engine parses it with serde; nothing
  is converted term by term.
- **Handles are opaque.** The platform never looks inside a story or a
  state. With a NIF they would be resources; with a sidecar, ids.
- **The log is the record, not the state.** The engine is deterministic
  (same story, seed and Links give the same state), so a reading can be
  rebuilt by replaying its log: `start/2` with the seed from
  `reading_started`, then `take/3` or `take_fork/3` for each Link in order.
  Whether to replay per request, cache states, or ask the engine for
  snapshots is the open question these notes will answer.
- **Forks cross only when asked.** `view/2` returns canon Links only;
  `fork/3` returns one fork, for one flip.
- **The platform owns Inquests.** The budget comes from `meta/1`; what is
  left is counted from the log. The engine never spends.
