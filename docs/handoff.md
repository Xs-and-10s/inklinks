# Handoff to the compiler chat

The first slice of the Inklinks platform is done (milestones 1 to 5, PRs
#1 to #5). It runs Ex 1 to 3 and a hand-written Littlejon fixture (IR "3")
on a stub engine behind `Inklinks.Engine`. These are the four documents to
take back, in the order to read them.

| File | What it settles |
|---|---|
| [`events.md`](events.md) | **The spec for the interpreter's event log**: envelope, guarantees, all 25 event types with actor and keys, replay rules, invariants under test, a real example log |
| [`engine-calls.md`](engine-calls.md) | **What the platform asks of an engine**, counted and timed; the Rust API it wants; the bridge recommendation |
| [`ir3-requests.md`](ir3-requests.md) | **Five requests for IR 3**, with the shapes the fixture already uses |
| [`compiler-followups.md`](compiler-followups.md) | Nine smaller issues found on the way, each with its workaround |

## The decisions that need the compiler's answer

1. **IR 3 §1, §2**: the `inquest` field on forks, and stable Link ids.
   Without these an Inquest-enabled Inklink cannot ship.
2. **The bridge**: a Rustler NIF, with `replay(story, seed, actions, upto)`
   and immutable states (engine-calls.md, "The bridge").
3. **One log**: the interpreter's events join the reading's stream with
   `actor: engine` (events.md §9).
4. **Determinism across engine versions** (events.md §5, §9.4): the
   promise, or the engine version recorded and kept playable.
5. **`finale` vs `epilogue`**, and whether a speech line uses `shown_as`
   (follow-ups 1, 3).

## How the platform checks itself against the spec

- `Inklinks.Events.Catalog` is the event table; a test fails if
  events.md's table and the code differ, or if the code writes a type the
  catalogue lacks.
- The compiler's eight Ex 3 tests run against the stub
  (`test/inklinks/engine/stub_ex3_test.exs`); run them against the Rust
  engine when the bridge exists, and use the stub as an oracle in a
  property test.
