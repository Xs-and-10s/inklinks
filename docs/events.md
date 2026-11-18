# The event log

Everything a reader does is an event, appended to one table that only grows.
Everything the platform shows, and everything an Inker will learn, is a
projection of that log. This file is the spec for the log, written so the
Rust interpreter's own event log can match it.

Status: the store is built (milestone 1); the reading events (milestone 2)
and Inquest events (milestone 3) are built. Ratings come with 4, and the
whole is finished in 5.

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

Every Inquest event carries `nib`, the Nib it happened on. Free text is
trimmed and capped at 2,000 characters; an empty answer is a skip.

| Type | When | `data` (besides `nib`) |
|---|---|---|
| `inquest_opened` | The Linker presses Inquest; the box opens | `remaining` (Inquests left) |
| `inquest_submitted` | They answer "What would you change here?" | `text` |
| `inquest_skipped` | They skip it (Skip, Escape, or an empty answer) | |
| `inquest_turned_down` | Nothing to look at: the request is noted, nothing spent | `reason`: `no_forks`, or `none_left` when the budget is spent |
| `inquest_mode_entered` | The Nib hides at least one fork: Inquest mode | `remaining` |
| `fork_looked` | A canon Link is flipped to its fork for the first time in this Inquest mode (looking again is not recorded) | `canon`, `fork`, `label` |
| `fork_taken` | The Linker takes a fork they looked at. **This, and only this, spends an Inquest** | `canon`, `fork`, `label` |
| `fork_declined` | A fork looked at, left untaken when Inquest mode ends | `canon`, `fork`, `by`: `left`, `wanted_instead`, `took_canon`, or `took_another_fork` |
| `wanted_instead_opened` | In Inquest mode, they choose a canon Link with no fork | `canon` |
| `wanted_instead_submitted` | They say what they wanted instead | `canon`, `text` |
| `wanted_instead_skipped` | They skip that | `canon` |
| `inquest_mode_left` | Inquest mode ends without a fork taken | `reason`: `left` (button or Escape), `wanted_instead`, `took_canon` |

A `fork_taken` is followed, in the same append, by any `fork_declined`s and
then `nib_shown` for where the fork led. Taking a fork ends Inquest mode by
moving on, so no `inquest_mode_left` follows it.

**Inquests left** is never stored: it is `reading_started.inquests` less
the stream's `fork_taken` count. A property test runs random sequences of
everything a Linker can do (and forged requests) and checks that the
count falls by exactly one on each `fork_taken` and at no other time, that
every `fork_taken` follows a `fork_looked` of the same fork since the last
`nib_shown`, and that no fork ever appears in a `nib_shown`'s `links`.

**Where flow D stands** (box open, Inquest mode, asking what they wanted)
is projected from these events since the last `nib_shown`, so a reload or
a second tab lands in the same place.

### To come

- **Milestone 4 (ratings):** a rating given; a reading abandoned
  (inferred); a return for another ending.
