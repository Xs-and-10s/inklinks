# The event log

Everything a reader does is an event, appended to one table that only grows.
Everything the platform shows, and everything an Inker will learn, is a
projection of that log. This file is the spec for the log, written so the
Rust interpreter's own event log can match it.

Status: the store is built (milestone 1). The event catalogue is filled in
as the reader (m2), Inquests (m3) and ratings (m4) produce events, and is
finished in m5.

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

To come with milestones 2 to 4. At minimum: a reading started; a Nib shown,
and for how long; a Link taken; an Inquest opened, submitted (with its text)
or skipped; an Inquest turned down, with no forks; a fork looked at, taken
or declined; an ending reached; a rating given; a reading abandoned
(inferred); a return for another ending.
