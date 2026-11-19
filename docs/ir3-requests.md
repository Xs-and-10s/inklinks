# IR 3: what the platform needs

IR version 2 is frozen. Everything here is a request for version 3, found by
building the platform against IR 2 and a hand-written Inquest fixture,
`priv/inklinks/ex4-littlejon-thornbury.json`: Littlejon from ch2 (the widow
at the millpond) to the opening of ch4, with two forks for one Link, a fork
asked for from a later chapter, and ch3's own fork. Every field the fixture
uses that IR 2 lacks is listed here.

## 1. Inquests: a fork is a Link with an `inquest` field

```json
{
  "type": "link",
  "id": "free_the_widow",
  "label": "Free her, unseen",
  "target": "ch2_alt",
  "kind": "go",
  "inquest": { "stands_in_for": "obey_at_thornbury", "by": "inker", "from": ["ch3"] },
  "...": "every other Link field, as in IR 2"
}
```

| Field | Meaning |
|---|---|
| `inquest` | Present only on a fork. A Link without it is an offered Link (canon is implicit, as decided 15 Nov) |
| `inquest.stands_in_for` | The id of the offered Link this fork stands in for, in the same passage. **Always written out**, even when the source leaves it implicit ("the Link just above"): the compiler resolves the default, so a runtime never infers it from position |
| `inquest.by` | `inker` for a fork the Inker wrote; `monkeypaw` or `storyteller` for one filled in later, with `rejoin` (where it rejoins canon) and the pending-slot fields that `~ inquest by monkeypaw ~ rejoin ch5` needs |
| `inquest.from` | Optional. Later passages from which this fork may also be asked for (`~ inquest from ch3`). The fork stays in its own passage, beside the Link it stands in for; `from` only says where else it can be asked for |

**Several forks for one offered Link** are allowed (decided 18 Nov): two or
more Links with `inquest.stands_in_for` naming the same Link. **Their order
is the order they are written in the passage**, and the IR keeps it (the
`body` is already in source order). The platform shows them as one group,
in that order, opened in the offered Link's place.

Why a field and not `kind: "inquest"` (reserved in IR 2): being a fork is
orthogonal to what a Link does. A fork can be a plain move (`go`), or an act
(`take book`), so it needs its own `kind`. **Request: retire the reserved
`kind: "inquest"`.**

What the platform does with `stands_in_for`:

1. **The flip.** In Inquest mode, an offered Link opens into the group of
   forks that stand in for it, in its place on the page.
2. **The box.** An offered Link no fork stands in for asks "what did you
   want instead" when chosen in Inquest mode.
3. **The record.** `fork_taken` and `fork_declined` name the pair:
   "took `free_the_widow` instead of `obey_at_thornbury`".
4. **Availability.** A fork is offered only while its offered Link is: if
   that Link's `when` fails, the fork is hidden too. A fork may still carry
   its own `when` (and `hidden_until`), which must also hold.

The budget is IR 2's resource declaration, unchanged:

```json
{ "declare": "resource", "id": "inquests", "value": 3 }
```

The platform turns Inquests on only when that is declared **and** the
Inklink has at least one fork (opt-in by the Inker, as decided).
`inkjot check` should refuse a fork in `mode: cohort` (decided: solo only),
and a fork whose `stands_in_for` names no offered Link in the same passage.

### Asking from a later passage

`from` lists passage names. `inkjot check` should refuse a name that is not
a passage, and could warn when no path leads from the fork's passage to the
`from` passage. At runtime the platform finds, for the Nib the Linker is at,
the latest visit to each passage whose forks name it in `from`, shows that
visit's offered Links ("Back when you chose …"), and, if a fork is taken,
replays the reading to that visit and takes it there. A fork without `from`
can be asked for only from its own passage.

### Open question

- **How far back.** `from` names passages, so the Inker decides. Should a
  fork asked for from a passage the reading has visited twice go back to
  the latest visit (what the platform does) or let the Linker pick?

## 2. Link ids that survive revisions

IR 2's `id` is positional (`ch2#2`), so reordering Links changes every id
after them, and an Inker's data (Inquest requests, ratings, forks taken)
would point at the wrong Link. The fixture uses the Inker's own ids
(`~ id obey_at_thornbury`). Request:

- `id` is the Inker's `~ id` when written;
- otherwise it is derived from the passage and the target, not the
  position (`ch2->ch3`), as decided 15 Nov, with a suffix only when two
  Links share both;
- optionally `"id_from": "inker" | "target"`, so tools can warn when an
  Inquest-enabled Inklink has forks or offered Links without Inker ids
  (`inkjot check` should warn, as decided).

## 3. Styled runs instead of asterisks

Lower emphasis at compile time, so no runtime parses Inkjot. A paragraph is
already a list of parts; add one more kind of part:

```json
["He opened his mouth to say ", {"style": ["italic"], "parts": ["I don’t remember"]}, ", and found that was not true."]
```

- `style` is a list of `"italic"` and `"bold"`; `***x***` is both.
- `parts` may hold anything a paragraph holds, inserts included, so
  `*{leo.aka}*` works.
- Escapes are settled by the compiler: `\*` arrives as `*`.
- The names describe typography, as the Inker wrote it. A renderer maps
  them to `<i>` and `<b>`: in fiction, italics are mostly thoughts, titles
  and foreign words, not stress.
- **Link labels too**: a label becomes a list of parts, like a paragraph,
  so a label can carry emphasis and, if string interpolation (proposed
  18 Nov) is adopted, values.

The fixture keeps IR 2's asterisks (five of them, from Littlejon's own
text); the stub lowers them by the v0.6 rules.

## 4. `state` declarations

v0.6's `state widow_freed: no` appears as

```json
{ "declare": "state", "id": "widow_freed", "value": false }
```

read as a bare name (`{"not": "widow_freed"}`) and set as one
(`{"do": "set", "target": "widow_freed", "value": true}`). The stub
treats it as IR 2 treats a `fact` without `belongs_to`.

## What the fixture does not need yet

Analysis tags (`~ beat`, `~ weighs`, `~ predict` …), `theme`, and MonkeyPaw
pending slots are in Littlejon but not in the fixture: the slice reads
none of them. When the platform shows Inkers their reports, `~ predict`
against the actual share of Linkers who took a Link is the first to want.
