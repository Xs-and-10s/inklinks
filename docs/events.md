# The event log

Everything a reader does is an event, appended to one table that only grows.
Everything the platform shows, and everything an Inker will learn, is a
projection of that log. This file is the spec for the log, written so the
Rust interpreter's own event log can match it.

Status: the store (milestone 1), reading events (2), Inquest events (3),
and ratings, stopping and returning (4) are built. Milestone 5 turns this
into the spec for the interpreter's event log.

## The store

One table, `events` (`priv/repo/migrations/*_create_events.exs`):

| Column | Type | Meaning |
|---|---|---|
| `position` | `bigint`, generated always | Global order. Nobody chooses it |
| `id` | `uuid` (v7) | The event's own id |
| `stream_type` | `text` | `reading`, later also `reader` |
| `stream_id` | `uuid` | The reading (or reader) the event belongs to |
| `stream_version` | `integer` | 1, 2, 3… within the stream, with no gaps |
| `type` | `text` | What happened, in snake_case: `link_taken` |
| `type_version` | `smallint` | The shape of `data` for that type, from 1 |
| `data` | `jsonb` object | The event's facts |
| `reader_id` | `uuid` | Who, copied from the stream for queries |
| `inklink_id` | `text` | Which Inklink, copied from the stream |
| `occurred_at` | `timestamptz` | When it happened, by the server's clock. An inferred event uses the inferred moment |
| `recorded_at` | `timestamptz` | When it was written |

### Guarantees

- **It only grows.** A row trigger refuses `UPDATE` and `DELETE`, a
  statement trigger refuses `TRUNCATE`, and `PUBLIC` loses those
  privileges. Triggers bind the table's owner and superusers too. In
  production the app connects as a role with only `SELECT` and `INSERT`.
- **Optimistic concurrency.** `UNIQUE (stream_id, stream_version)`. A writer
  appends after the version it last saw; if another writer got there first,
  the append fails with the stream's real version and writes nothing.
- **All or nothing.** A batch is one transaction.
- **Total order.** `position` orders all events; `stream_version` orders
  one stream. Projections catch up by position.

### Indexes

- `(reader_id, position)`: one reader's history
- `(inklink_id, type, position)`: an Inker's queries ("every `fork_taken`
  in Littlejon")
- GIN on `data` (`jsonb_path_ops`): containment queries
  (`data @> '{"nib": "ch2"}'`)

### Properties under test

- The log only ever grows, and no stored event changes, whatever sequence
  of appends, stale appends, malformed batches, `UPDATE`s, `DELETE`s and
  `TRUNCATE`s is tried.
- A stream's versions run 1, 2, 3… without gaps, in append order; a stale
  writer is refused and changes nothing, even with an empty batch.
- When several writers race for the same version on real connections,
  exactly one wins.

## The catalogue

Every event belongs to a reading stream (`stream_type = 'reading'`).
`data` keys are strings. Times are not in `data`: every event has its
`occurred_at`.

### Built (milestone 2)

| Type | When | `data` |
|---|---|---|
| `reading_started` | A Linker begins a reading | `seed` (integer: replays the dice), `ir` (IR version), `ir_sha256` (the exact file played), `engine` (which engine), `inquests` (the budget the Inker declared, 0 if none) |
| `nib_shown` | A Nib is put in front of the Linker: at the start, and after every Link | `nib` (the passage with the Links), `passed` (passages shown on the way, by `next:`), `links` (the ids of the canon Links on offer) |
| `link_taken` | The Linker takes a canon Link | `link` (its id), `nib` (where it was taken), `label` (its text as shown, for reports that outlive revisions) |
| `ending_reached` | A `finale` Nib is shown | `ending` (the finale's passage name) |
| `reading_finished` | A Nib with no Links is shown: nothing more to choose | `ending` (the finale it ended on, or null for a dead end) |

Each step is one append: `link_taken`, then `nib_shown`, then
`ending_reached` and `reading_finished` when they apply, at consecutive
versions. A reading is **finished** when its stream holds a
`reading_finished`; the library's "Continue" finds the latest
`reading_started` without one.

**Time per Nib** is not stored; it is read off the log: the `nib_shown`'s
`occurred_at` to the next event's. The same goes for where readers stop
(the last `nib_shown` of a stream with no `reading_finished`).

**The record is enough to rebuild.** `reading_started.seed` and the
`link_taken` ids, in order, replay the reading exactly; a property test
checks that a reading rebuilt from its log shows what the live one shows.
And every `link_taken` names a Link listed in the `nib_shown` just before
it: a reader can never take a Link the IR does not offer.

### Built (milestone 3): Inquests, flow D

Every Inquest event carries `nib`, the Nib the Linker is at. `link` is the
offered Link a fork stands in for. Free text is trimmed and capped at 2,000
characters; an empty answer is a skip.

**Forks asked for from a later Nib.** When the fork stands in for a Link
at an earlier passage (`~ inquest from ch3`), its events also carry `at`,
the earlier passage, and `back_to`, the `stream_version` of that visit's
`nib_shown`. So a record reads: asked at `ch3`, back to `ch2` (version 2),
took `free_the_widow` instead of `obey_at_thornbury`.

| Type | When | `data` (besides `nib`) |
|---|---|---|
| `inquest_opened` | The Linker presses Inquest; the box opens | `remaining` (Inquests left) |
| `inquest_submitted` | They answer "What would you change here?" | `text` |
| `inquest_skipped` | They skip it (Skip, Escape, or an empty answer) | |
| `inquest_turned_down` | Nothing to look at: the request is noted, nothing spent | `reason`: `no_forks`, or `none_left` when the budget is spent |
| `inquest_mode_entered` | Forks are hidden here, or asked for from here: Inquest mode | `remaining` |
| `fork_looked` | A fork is shown for the first time in this Inquest mode: opening a Link shows all its forks, so one event per fork (showing them again is not recorded) | `link`, `fork`, `label`, and `at`, `back_to` when earlier |
| `fork_taken` | The Linker takes a fork they were shown. **This, and only this, spends an Inquest** | `link`, `fork`, `label`, and `at`, `back_to` when earlier |
| `fork_declined` | A fork shown, left untaken when Inquest mode ends | `link`, `fork`, `by`: `left`, `wanted_instead`, `took_link`, or `took_another_fork`; and `at`, `back_to` when earlier |
| `wanted_instead_opened` | In Inquest mode, they choose an offered Link with no fork | `link`, and `at`, `back_to` when earlier |
| `wanted_instead_submitted` | They say what they wanted instead | `link`, `text`, and `at`, `back_to` when earlier |
| `wanted_instead_skipped` | They skip that | `link`, and `at`, `back_to` when earlier |
| `inquest_mode_left` | Inquest mode ends without a fork taken | `reason`: `left` (button or Escape), `wanted_instead`, `took_link` |

A `fork_taken` is followed, in the same append, by any `fork_declined`s and
then `nib_shown` for where the fork led. Taking a fork moves on, which ends
Inquest mode, so no `inquest_mode_left` follows it.

**Going back.** A `fork_taken` with `back_to` is replayed from the engine
state at that earlier `nib_shown`, not the current one: the world goes back
to that visit (the widow is in the water again), then the fork is taken.
Inquests already spent stay spent; they are the Linker's, not the story's.

**Inquests left** is never stored: it is `reading_started.inquests` less
the stream's `fork_taken` count. A property test runs random sequences of
everything a Linker can do, at the current Nib and at earlier ones, forged
requests included, and checks that the count falls by exactly one on each
`fork_taken` and at no other time; that every `fork_taken` follows a
`fork_looked` of the same fork since the last `nib_shown`; that no fork ever
appears in a `nib_shown`'s `links`; and that the log rebuilds the same
reading.

**Where flow D stands** (box open, Inquest mode, asking what they wanted)
is projected from these events since the last `nib_shown`, so a reload or
a second tab lands in the same place.

### Built (milestone 4): ratings, stopping, returning

| Type | When | `data` |
|---|---|---|
| `rating_asked` | A `finale` is shown, the reading has not been asked yet, and this Linker has not rated this ending before (in any reading). Written with the Nib, so a reload asks again until answered | `ending`, `path` (true if the Linker took or declined a fork: the box then asks about their path) |
| `rating_given` | They answer the box. Every score is optional, 1 to 5 | `ending`, `ending_score`, `inklink_score`, and `path_score` only when `path` was asked |
| `rating_dismissed` | "Not now", Escape, or an answer with nothing in it | `ending` |
| `change_wished` | Under "More…", a moment they would change | `nib`, `back_to` (the version of that Nib's `nib_shown`), `chose` (what they chose there), `text` (or null) |
| `reading_abandoned` | **Inferred**: no `reading_finished`, and nothing for `:abandon_after` (a day by default). `occurred_at` is the last event's time, when they actually stopped; `recorded_at` is when it was inferred | `nib` (where they stopped), `idle_seconds` |
| `reading_resumed` | The Linker acts again in a reading inferred abandoned; written before their action | `nib`, `after_seconds` |
| `returned_for_another_ending` | A reading starts for a Linker who has finished this Inklink before; written after `reading_started` | `readings_finished`, `endings_seen` |

`nib_shown` also carries `visit`: 1 the first time a reading shows that
Nib, more when it is shown again (a hub, or going back). That is a
**re-read**.

The ratings box opens a few seconds after the end of the finale scrolls
into view, or from "Rate this ending", so it never covers the ending before
it is read. It is asked once per reading; a dismissed box does not stop the
next reading asking, a rated ending does.

## Reading the log: what an Inker will see

`Inklinks.Insights` answers the brief's questions with plain SQL over this
table, and its tests run them against real readings. That is the check
that the log holds enough:

| Question | From |
|---|---|
| Where readers stop | `reading_abandoned.nib` |
| Time per Nib | `nib_shown` to the Linker's next action in the stream (median) |
| Re-reads | `nib_shown.visit > 1`; readers with several `reading_started` |
| What happened to forks | `fork_looked`, `fork_taken`, `fork_declined` by `fork` |
| What readers asked for | `inquest_submitted.text` (and the event after it: turned down or Inquest mode), `wanted_instead_submitted.text`, `change_wished.text` |
| How endings land | `rating_given` by `ending` |
| Returns | `returned_for_another_ending`; readers with more than one distinct `ending_reached` |

**A lesson for the interpreter's log.** Time per Nib needs to tell the
Linker's actions from what the platform or engine writes in the same
moment (`ending_reached`, `rating_asked`, `reading_finished` share the
Nib's timestamp). Here that is a list of action types in the query. A
Rust event log would do better to say it on every event: an `actor`
field, `linker | engine | platform`. Proposed for the spec in milestone 5.

