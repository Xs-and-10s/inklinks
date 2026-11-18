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
