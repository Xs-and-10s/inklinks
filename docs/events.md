# The event log

Everything a reader does is an event, appended to one table that only grows.
Everything the platform shows, and everything an Inker will learn, is a
projection of that log. This file is the spec for the log, written so the
Rust interpreter's own event log can match it.

Status: the store is built (milestone 1); the reading events are built
(milestone 2). Inquest events come with milestone 3, ratings with 4, and
the whole is finished in 5.

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

### To come

- **Milestone 3 (Inquests):** an Inquest opened, submitted (with its text)
  or skipped; turned down, with no forks; a fork looked at, taken or
  declined.
- **Milestone 4 (ratings):** a rating given; a reading abandoned
  (inferred); a return for another ending.
