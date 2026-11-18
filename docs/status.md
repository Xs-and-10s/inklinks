# Status

Where the platform stands, and what comes next. Update this file in the
same commit as the work it describes, so an interrupted session can pick up
from here.

## The slice

One vertical slice against a stub engine: a library, a reader for Ex 3,
Inquests (flow D) on a hand-written Littlejon fixture, ratings after any
finale, and an append-only event log of everything a reader does. Not in
this slice: cohort play, the jury, hints, MonkeyPaw or Storyteller forks,
the real engine.

## Milestones

| Milestone | Branch | What | State |
|---|---|---|---|
| 1 | `m1-skeleton` | Phoenix without LiveView or a JS build; the event log and its append-only triggers; the reader id; the `Inklinks.Engine` behaviour; the catalog and library page | done, #1 |
| 2 | `m2-reader` | The stub engine on Ex 3: Nibs, Links, `[if]` and `~ when`, emphasis, speech and beats; reading events | done |
| 3 | `m3-inquests` | The Littlejon fixture; flow D; forks fetched on flip; View Transitions and the live region | next |
| 4 | `m4-ratings` | Ratings after a finale; abandoned readings inferred; returning for another ending | |
| 5 | `m5-handoff` | `events.md`, `engine-calls.md`, `ir3-requests.md` finished for the compiler chat | |

## Decisions (18 Nov 2026)

- Repo `Xs-and-10s/inklinks`, public, AGPL-3.0-or-later. Story text is not
  under that license (`NOTICE`).
- Postgres with Ecto. The log is append-only in the database itself.
- No accounts yet: an anonymous UUIDv7 reader id in the signed session.
  Later, `reader_claimed` ties it to an account.
- Datastar 1.0.5 with Rocket (beta), free and MIT since 1.0, vendored.
- Plain no-build CSS: `@layer`, nesting, custom properties; semantic
  selectors, not utility classes.
- Ex 3's last passage is tagged `finale` as well as `epilogue`. `finale` is
  the ending; `epilogue` a coda after one.
- IR 2 passes `*emphasis*` through as text; the stub lowers it to styled
  runs, the shape requested for IR 3.

## The stub engine

`Inklinks.Engine.Stub` plays solo stories: Nibs, `go` Links with
`~ when` and `hidden until`, `[if]` / `[unless]` / `[else]` / `[end]` /
`[once]` / `[beat]`, `next:`, facts (`set`), lists (`add`, `strike`,
`remove`), `move`, `{value}` and `{list}` inserts, `aka`. Anything else
it names and refuses at load; the library shows why (Ex 1 and Ex 2).
It passes the compiler's own eight Ex 3 tests, ported to
`test/inklinks/engine/stub_ex3_test.exs`.

## How to resume

```
mix setup
mix test
mix phx.server
```

Work happens on a branch per milestone, pushed early and often, with a pull
request into `main`.
