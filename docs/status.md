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
| 2 | `m2-reader` | The stub engine on Ex 3: Nibs, Links, `[if]` and `~ when`, emphasis, speech and beats; reading events | done, #2 |
| 3 | `m3-inquests` | The Littlejon fixture; flow D; forks fetched on flip; View Transitions and the live region | done, #3 |
| 4 | `m4-ratings` | Ratings after a finale; abandoned readings inferred; returning for another ending; Inker insights from the log | done |
| 5 | `m5-handoff` | `events.md`, `engine-calls.md`, `ir3-requests.md` finished for the compiler chat | next |

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

## Inquests

`Inklinks.Inquest` runs flow D: the box first, then Inquest mode, forks
fetched one Link at a time, a fork spent only when taken.

Decided with Mark (18 Nov):

- **Taking a fork ends Inquest mode**: it moves on, and the next Nib asks
  first again.
- **Several forks per offered Link**, opened as one group in the Link's
  place, in the Inker's order; each fork its own button. **One group open
  at a time**: opening (or tapping) another Link closes it.
- **Forks asked for from a later Nib** (`inquest.from`): shown under "Back
  when you chose …", taken by going back to that visit.
- **Offered Links**, not canon Links; event data says `link`.
- **No timeout** for choosing in Inquest mode.

Decided while building it (easy to change):

- **No Inquests left:** the box still opens (the Inker still hears what
  the Linker wanted), and the answer is "Noted"; Inquest mode never opens.
  Logged as `inquest_turned_down` with `reason: none_left`.
- **A fork must be looked at before it can be taken.** A forged
  `take-fork` with an id the page never received is refused.
- **Leaving Inquest mode** is a button and Escape. In Inquest mode canon
  Links flip or ask; to take a canon Link, the Linker leaves first.
- **Touch and mouse clicks are not looks.** Hover counts only for a mouse,
  focus only when `:focus-visible`, so a tap is a tap: first flips, second
  takes.
- **A Link with no fork says so in its own label** ("no other path here")
  once looked at, rather than in the live region, which a quick Tab across
  several Links could leave stale.
- **Going back goes to the latest visit** of the earlier passage.
- **The open group's first fork takes the place of the Link's own button**,
  so keyboard focus stays put when the group opens; Tab walks the group,
  and leaving it closes it.

## Ratings, stopping, returning

Decided while building milestone 4 (easy to change):

- **Going back lets the Linker pick** (decided with Mark, 19 Nov): every
  earlier visit where a fork can be taken, repeats collapsed into the
  latest, newest first, at most three, each with how many choices it
  undoes. Tested on "The Well", a test-only fixture in
  `test/fixtures/inklinks/`.
- **The ratings box waits**: it opens four seconds after the end of the
  finale scrolls into view, or at once from "Rate this ending".
- **Abandoned after a day** (`:abandon_after`), swept every ten minutes
  (`:sweep_every`); a later action records `reading_resumed` first.
- **A dismissed rating** does not stop the next reading of that ending
  asking; a given one does.

## How to resume

```
mix setup
mix test
mix phx.server
```

Work happens on a branch per milestone, pushed early and often, with a pull
request into `main`.
