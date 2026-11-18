# IR 3: what the platform needs

IR version 2 is frozen. Everything here is a request for version 3, found by
building the platform against IR 2 and a hand-written Inquest fixture.
Status: started in milestone 1; the Inquest fields come with milestone 3.

## 1. Styled runs instead of asterisks

Lower emphasis at compile time, so no runtime parses Inkjot. A paragraph is
already a list of parts; add one more kind of part:

```json
["“I’ll get ", {"style": ["italic"], "parts": ["me"]}, " noticed,” said Eyrad."]
```

- `style` is a list of `"italic"` and `"bold"`; `***x***` is both.
- `parts` may hold anything a paragraph holds, inserts included, so
  `*{leo.aka}*` works.
- Escapes are settled by the compiler: `\*` arrives as `*`.
- The names describe typography, as the Inker wrote it. A renderer maps
  them to `<i>` and `<b>`: in fiction, italics are mostly thoughts, titles
  and foreign words, not stress.
- The same goes for Link labels, which are text and can carry emphasis.

## 2. Link ids keyed by passage and target

IR 2's `id` is positional (`ch2#2`), so reordering Links changes every id
after them. The 15 Nov decision keys a Link without `~ id` by its passage
and its target. The IR should carry that key (or the Inker's `~ id`), so the
Inker's data keeps pointing at the right Link across revisions.

## 3. Inquests

To come with milestone 3: the fields the Littlejon fixture needed (a fork
marked as an Inquest, the canon Link it `stands_in_for`, written out even
when the source leaves it implicit), and two open questions: can one canon
Link have several forks, and may a fork carry its own `when`?
