# Back to the compiler

Issues found while building the platform, to take back to the
inkjot-compiler-rust chat as one batch. None of them blocks the slice; each
says how the platform works around it meanwhile. IR 3 field requests have
their own file, `ir3-requests.md`.

## 1. `finale` and `epilogue`

Ex 3's last passage, `the_list`, is tagged `epilogue` and not `finale`, so
nothing marks it as an ending.

Proposed meaning:

- **`finale`** is an ending: what a Linker reaches, what the ratings box is
  about, and its passage name is the ending's id. An Inklink may have many.
- **`epilogue`** is a coda after a finale: one shared, or one per finale.
- The ratings box opens when a reading reaches a passage with no Links
  left, and is about the last `finale` the Linker passed. A passage tagged
  both is the ending and the end at once, which is well defined.

Also: `run.md` says the finale is the passage *no Link leads to* (Ex 1's
clock-out `terminus`), but Littlejon's endings are `[finale]` passages that
Links do lead to. Both should be allowed: a story reaches its endings by
Links; a clocked game by the clock.

**Meanwhile:** `priv/inklinks/ex3-the-fall-of-the-old-regime.json` has
`"tags": ["epilogue", "finale"]` on `the_list`, added by hand. Fix:
`:: the_list [epilogue finale]` in the Ex 3 source, then `UPDATE_IR=1`.

## 2. Emphasis

IR 2 passes `*italic*`, `**bold**` and `***both***` through as literal
asterisks, so a runtime has to parse Inkjot to render them. See
`ir3-requests.md` for the requested shape.

**Meanwhile:** the stub engine lowers asterisks itself, following the v0.6
rules (underscores literal, an unmatched `*` literal, `\*` an asterisk,
never across a paragraph).

## 3. `shown_as` in speech

Ex 3 declares `npc widow: "Marge" ~ shown as "the Surviving Authority"`.
The interpreter's speech lines use the label, so she speaks as "Marge"; the
`shown_as` text is never shown. Which should a speech line use: the label,
`shown_as`, or `shown_as` until something reveals the name?

**Meanwhile:** the stub matches the interpreter and uses the label.

## 4. The stub matches the interpreter, so test them together

The stub copies the interpreter's xorshift64 generator and its `aka`
shuffle, so the same seed names Leo the same way in both. When the bridge
exists, run the platform's Ex 3 scenarios (`test/inklinks/engine/`)
against the Rust engine as well: they are the compiler's own Ex 3 tests,
and the stub passes them all.

## 5. Inquests: the reserved `kind: "inquest"`

IR 2 reserves `kind: "inquest"` for Links. A fork can be a move or an act,
so being a fork should be a field (`"inquest": {"stands_in_for": …}`), not
a kind. See `ir3-requests.md` §1.

## 6. Ex 4 and the fixture

Flow D has a branch for an offered Link with no fork, chosen in Inquest
mode ("what did you want instead"). Every Inquest Nib in Ex 4 has exactly
one offered Link and its fork, so that branch never comes up in the real
text. The fixture adds to ch2, marked fixture-only:

- `watch_what_unfolds`, "Make yourself watch" (to ch3): an offered Link with
  no fork. In the fixture it is the same choice as "Stay at Eyrad's side"
  under another name; in Ex 4 it could set something ch3 reads, so it is
  not empty.
- `speak_in_her_ear`, "Speak in Sister Agathe's ear" (to a new passage,
  `ch2_voice`): a second fork for `obey_at_thornbury`. Ixë does not free
  the widow; he speaks into the Sister's ear in the Light's old tongue
  ("She is mine. Give her back."), she stops the trial herself and claims
  the Light spoke to her, and Eyrad sees he has used its voice. It sets
  `widow_freed`, and fits ch4's line about "a voice in the Sister's ear".

And `free_the_widow` is marked `from ch3`, so it can also be asked for from
ch3, which is not in the draft.

## 7. Vocabulary: offered Links (decided 18 Nov)

The Links a Nib shows are **offered Links**; a **fork** is hidden behind
one. "Canon" stays a story word, for the Inker's main line. The platform's
event data says `link` where it said `canon`. Worth using the same words in
run.md and the Inkjot docs.

## 8. What the engine needs to grow (from engine-calls.md)

For the bridge, in order:

- **`replay(story, seed, actions, upto)`**, returning one state per Nib
  shown: the platform rebuilds a reading on every request, and going back
  needs earlier states.
- **Immutable states** (`take` returns a new one and the old stays usable).
- **A step limit**: a `next:` cycle or runaway loop returns an error, never
  hangs a scheduler.
- **Determinism across versions**: the same IR, seed and actions give the
  same views, or the engine version goes into `reading_started` and old
  readings replay on the version they began on.
- **`snapshot`/`restore`**, later, for long games.

The recommendation is a Rustler NIF (calls are microseconds; `load` and
`replay` on dirty schedulers; states as resources), with the stub kept as
an oracle in a property test against the Rust engine.

## 9. Engine events in the reading's log (from events.md)

The interpreter's own events (checkpoints, rewinds, turn ends, deaths, and
in cohort play locks, claims and clashes) should join the reading's stream
with `actor: engine`, under the envelope and guarantees in events.md §2–3.
Adding one means adding it to `Inklinks.Events.Catalog` with its keys.

