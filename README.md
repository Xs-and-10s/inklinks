# Inklinks

The web platform for Inklinks: choice-based creative works (stories, games
and story-games) co-authored by an **Inker**, who writes, and **Linkers**,
who choose.

Inklinks are written in Inkjot and compiled to a JSON IR by
[inkjot-compiler-rust](https://github.com/Xs-and-10s/inkjot-compiler-rust).
This platform never parses Inkjot; it reads the IR, through an engine
(`Inklinks.Engine`). For now that engine is a small Elixir stub. The Rust
interpreter replaces it later.

## Stack

- Elixir and Phoenix, without LiveView, esbuild or Tailwind
- Postgres, with an append-only event log
- [Datastar](https://data-star.dev) 1.0.5 with Rocket, served from
  `priv/static/vendor/`, driven from the server by
  [dstar](https://hex.pm/packages/dstar)
- One no-build stylesheet, `priv/static/assets/app.css`: semantic selectors
  and cascade layers

## Running it

```
mix setup        # deps, database, migrations
mix phx.server   # http://localhost:4000
mix test         # scenarios and StreamData properties
```

Postgres is expected on `localhost` as `postgres`/`postgres`
(`config/dev.exs`, `config/test.exs`). The versions used are in
`.tool-versions`.

## Where things are

| Path | What |
|---|---|
| `lib/inklinks/events.ex` | The event log: append to a stream, read it back |
| `lib/inklinks/events/catalog.ex` | Every event type, its origin and its keys |
| `lib/inklinks/timeline.ex` | A reading's path as a tree, from the log (the path page) |
| `lib/inklinks/engine.ex` | The engine boundary (a behaviour) |
| `lib/inklinks/catalog.ex` | The Inklinks on offer, from `priv/inklinks/*.json` |
| `priv/inklinks/` | IR files, one per Inklink |
| `docs/status.md` | What is done, what is next, how to resume |
| `docs/handoff.md` | Start here for the compiler chat: what each doc below settles |
| `docs/events.md` | The events schema: the spec for the interpreter's event log |
| `docs/engine-calls.md` | How the platform calls the engine: settles the bridge |
| `docs/ir3-requests.md` | Fields the platform needs from IR version 3 |
| `docs/compiler-followups.md` | Issues to take back to the compiler |
| `docs/later.md` | What is deferred, and why |

## License

The code is licensed under the GNU Affero General Public License, version 3
or any later version (`LICENSE`). Story content is not: see `NOTICE`.
