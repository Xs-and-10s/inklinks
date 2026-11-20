# Later

Ideas and decisions deliberately deferred, with enough of the reasoning to
pick them up cold. Each says what it depends on and whose concern it is:
the platform (this repo), the compiler (inkjot), or both.

## Inklink identity: works, series, adaptations, renames

*Platform. After accounts.*

`inklink_id` is opaque and never changes (events.md §2). Everything a
person would call the Inklink's name is an attribute or a relation:

| Thing | Model |
|---|---|
| Title | Free text, not unique. A story and a game may share one; the library shows title, kind badge and Inker |
| Kind | `story`, `story-game`, `game`: a column, so the library and personal libraries filter on it |
| URL | A slug (`/@mark/littlejon`). Old slugs stay as redirects |
| Rename | `inklink_renamed` in an `inklink` stream: history kept, nothing re-keyed |
| One Inker's story and game versions | Two Inklinks grouped under one **work** (`work_id`), like editions of a book |
| Someone else's adaptation | `adapted_from: inklink_id`, with credit to the original |
| Series | A series with ordered members (`series_id`, `position`) |
| Revisions | Readings pin the IR they began on (`ir_sha256`); a published revision is an event in the `inklink` stream |

Why not a composite key (`inker+kind+title`): each part can change (a
rename, a story becoming a story-game, a co-author, a transfer), and a key
that changes orphans every event that names it.

## Users and roles; choosing the Storyteller

*Both: the IR says what a role is, the platform says who holds it. With
cohort play.*

- **One `user_id`.** Inker, Linker and Storyteller are roles a user takes
  in a context, not separate ids. `reader_id` becomes the `user_id` once
  accounts arrive (`reader_claimed`).
- **The IR declares the role**: whether an Inklink needs a Storyteller,
  what the Storyteller can see (every role, hidden state) and do (fill
  `pending` forks, rule on moves), and whether the Storyteller also plays.
  The IR never names a person (decided 19 Nov; in the handoff).
- **The platform chooses who**, per cohort, by a policy the Inklink or the
  cohort sets: `volunteer`, `nominate` (the nominee must accept), `vote`,
  `random`, `highest_ranked`, or `inker` (a private, invite-only
  Inklink). Events in the cohort's stream: `storyteller_volunteered`,
  `storyteller_nominated`, `storyteller_accepted`, `storyteller_vote_cast`,
  `storyteller_chosen {user, by}`.
- Mafia is the test case: one of the cohort moderates, sees every role,
  and does not play.
- `highest_ranked` needs Storyteller ratings, which is a reputation
  system: decide separately whether that is wanted.

## The path map and the reading timeline

*Platform. Next after the handoff; before playtesting. Does not need the
real engine.*

Two pictures, from data the log and the IR already hold:

- **The story map, for the Inker.** Passages and Links from the IR; how
  many readers took each from the log. Offered Links blue, forks orange,
  never taken gray; width by count. A graph, not a tree: hubs and loops
  (the-well) are normal.
- **A reading's timeline, for the Linker.** A tree: the path taken,
  branching where an Inquest went back, and later where a rewind did. A
  filter by branch type: Inquests, rewinds, both. Shown after the rating,
  it is the clearest picture of what Inquests are for.
- **Spoilers.** A Linker's view shows only forks they looked at. The
  platform keeps forks out of the page source on purpose; the map must
  not undo that.
- **Cost.** About a milestone. The hard part is layout: a hand-rolled
  layered layout (rank by longest path, order by barycenter) as
  server-side SVG keeps the no-build stack; dagre or ELK would be a
  dependency.

## MonkeyPaw, Ghostwriters and baking

*Both. The IR shape is in IR 3 (`credit`, `pending`, `brief`); the rest is
platform work.*

- **A brief's vocabulary** (passages, Links, forks per Link, tone weights,
  whether it may write endings) is added field by field, under IR 3's rule
  that unknown fields are ignored.
- **Persisting generations.** Everything MonkeyPaw writes is kept, as
  events in the `inklink` stream (`passage_generated`, with the brief and
  the prompt's inputs), so an Inker can read, compare and rate them.
- **Baking.** An Inker picks the best generated paths and exports them as
  Inkjot source with `credit: monkeypaw`. Baked content is fixed: no
  generation cost, the same for every reader, and still credited.
- **Ghostwriters.** A person who fills `pending` slots between readings,
  for every future reader, with the Inker's approval: a review workflow
  (`ghostwriting_submitted`, `…_approved`, `…_returned`).
- **Inker run-throughs.** An Inker reads their own Inklink as a Linker to
  trigger generation before release, so readers meet baked or cached
  content.
- **Who pays** for generation (the Inker, the reader, a subscription) is
  a product decision, and decides how much of the above ships first.

## Stat changes in the log

*Compiler first (events.md §9.8), then platform.* If the interpreter puts a
diff of tracked values on its step events, Inker reports can ask "readers
who ended with Leo's trust below 3" without replaying. Until then, those
reports replay into a projection.
