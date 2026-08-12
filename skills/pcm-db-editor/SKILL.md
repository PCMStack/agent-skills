---
name: pcm-db-editor
description: Open, explore and edit Pro Cycling Manager databases (.cdb) — rider ratings, team rosters, contracts, races. Routes between the pcm-mcp MCP server and a cdb → SQLite conversion via the cdb-converter CLI. Use this skill whenever a .cdb file is mentioned, or whenever someone talks about a PCM / Pro Cycling Manager save, career, database, roster, cyclist stats, or wants to "edit my game" — even if they never say the words "cdb" or "database", and even if they only want to read something rather than change it.
---

# Pro Cycling Manager save & database editing

Pro Cycling Manager stores everything — cyclists, teams, contracts, races, the whole game
database — in a binary `.cdb` file. It is not readable as-is, but it is _exactly_ a SQLite
database wearing a costume: a lossless conversion exists in both directions. Once you know
that, every PCM question becomes an ordinary SQL question.

Your job is to pick the right door into that database, answer the question with real data
(never from memory about how PCM "usually" works), and — if the user wants changes — write
them back without ever putting their career at risk.

## Which door to use

There are two routes. Choose based on **where the file physically lives**, because that
determines what can actually touch it:

| Situation                                                                                                               | Route                           |
| ----------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| The save is on the user's own machine (they give a path, or ask you to find their saves)                                | **Route A — pcm-mcp**           |
| The `.cdb` was uploaded into the conversation, is in the working directory, or you can read it with your own file tools | **Route B — convert to SQLite** |

The reasoning: pcm-mcp runs on the user's machine, so it can reach the game's own save
directories, auto-discover careers, and write a new `.cdb` there. It cannot see a file that only exists in your
sandbox. Conversely, the converter route works anywhere you can run `npx`, and gives you
unrestricted SQL — including JOINs, aggregates and bulk edits the MCP tools don't expose.

If you're on Route A and the question outgrows the MCP tools — multi-table analysis,
schema exploration, editing dozens of rows at once — say so and fall back to Route B on a
copy of the file. That's a normal escalation, not a failure.

### Checking for pcm-mcp

Route A needs the `pcm_*` tools to be present in your tool list. Look; don't assume.

If they're absent, **mention it once and continue on Route B** — don't install anything and
don't block on it:

When they are present, let `pcm_list_saves` find the careers rather than guessing at install
locations — it knows where this platform and game year put them. If it returns nothing, ask
the user for the path instead of hunting through directories yourself.

## The one rule that matters: never damage the save

A PCM career can represent hundreds of hours. Treat the original `.cdb` as read-only, always:

- **Back it up before touching anything.** `cp save.cdb save_backup.cdb` costs nothing..
- **Write edits to a new file**, e.g. `save_edited.cdb` next to the original. The MCP write
  tools enforce this (they refuse to overwrite); on Route B _you_ enforce it.
- **Watch the CLI's default output path.** `npx cdb-converter save.sqlite` writes to
  `save.cdb` — which is very plausibly the user's original. Always pass an explicit output
  path on the way back.
- Tell the user to load the edited save in-game and verify before deleting anything.

## Route A — pcm-mcp

Every `pcm_*` tool is stateless: it takes an absolute `savePath`, re-reads the `.cdb` into a
fresh in-memory database, and answers. There's no "current save", so carry the path through
the conversation yourself.

Typical flow:

1. **Locate** — `pcm_list_saves` to discover careers, or `pcm_validate_save <absolute path>`
   when the user already gave you a file.
2. **Explore** — `pcm_get_save_schema` / `pcm_get_table_schema` to learn the shape,
   `pcm_search_cyclist`, `pcm_search_team`, `pcm_get_team_roster`, `pcm_get_player_info`
   for the common questions, `pcm_query_save` for anything else (read-only `SELECT` /
   `WITH … SELECT`, capped at 1000 rows).
3. **Edit** — `pcm_update_cyclist_ratings` for a rider's abilities, `pcm_update_save` for a
   single `INSERT`/`UPDATE`/`DELETE`. Both write to a new `outputPath` and refuse to
   overwrite. DDL and stacked statements are rejected.

When a user wants several edits at once, note that `pcm_update_save` applies one statement
per call and each call produces a new file. Chaining three edits means three files. Past
two or three changes, Route B is cleaner: do it all in SQLite, convert once.

## Route B — convert to SQLite, edit, convert back

The `cdb-converter` package does a **lossless** round trip: tables, column order,
data types and internal flags all survive `cdb → sqlite → cdb`, so the game reads the result
happily.

### Open

```bash
cp save.cdb save_backup.cdb                           # backup first, always — keep .cdb
npx -y cdb-converter save.cdb save.sqlite --normalize
```

`--normalize` reconstructs `PRIMARY KEY` / `FOREIGN KEY` constraints from PCM's naming
conventions. Use it by default: it makes the database self-describing, so you can discover
how tables relate instead of guessing, and it's round-trip safe . Costs ~10% time and ~40% size.

Add `--index-fk` only if you're running heavy JOINs on a big save — it roughly doubles the size.

`scripts/open_cdb.sh` bundles the backup, the conversion and a first inventory of tables by
row count — a good starting point when you don't know the save yet.

### Explore

Use the `sqlite3` CLI (or any SQLite library). Discover before querying — PCM's schema
varies across game years, so confirm names rather than trusting recall:

```bash
sqlite3 save.sqlite ".tables"
sqlite3 save.sqlite "PRAGMA table_info(DYN_cyclist);"
sqlite3 -header -column save.sqlite "SELECT ... LIMIT 20;"
```

Read `references/pcm-schema.md` for the naming conventions (`DYN_` vs `STA_`, `IDx` /
`fkIDx`, the `gene_sz_` prefix), the tables that answer most questions, and ready-made
queries for rosters, ratings, contracts and free agents. Read it as soon as you're writing
anything beyond a single-table `SELECT` — it will save you a round of trial and error.

### Edit and write back

```bash
sqlite3 save.sqlite "UPDATE DYN_cyclist SET ... WHERE IDcyclist = 1234;"
npx -y cdb-converter save.sqlite save_edited.cdb     # explicit output path!
```

Things that break the round trip, and why:

- **No DDL.** `CREATE` / `ALTER` / `DROP` — the CDB data types and column indices are encoded
  in each column's _declared type string_, so a table you create by hand has no valid
  metadata and won't convert back. Change data, not structure.
- **Leave `DB_STRUCTURE` alone.** That table carries per-table CDB flags whose meaning is
  unknown but which the game needs. Don't edit or drop it.
- **Respect the existing types.** Writing a string into an integer column, or a value beyond
  a column's byte/short range, produces a file the game may reject.
- **New rows need consistent IDs and foreign keys.** Pick an ID above the current max and
  make sure every `fkID*` you set points at a row that exists.

Then verify what you changed before handing it back — re-open the produced `.cdb` and
`SELECT` the rows you touched:

```bash
npx -y cdb-converter save_edited.cdb verify.sqlite
sqlite3 verify.sqlite "SELECT ... WHERE IDcyclist = 1234;"
```

This catches silent no-ops (a `WHERE` that matched nothing) and is quick.

## Reporting back

Show data as compact tables, with real values from the file — never illustrative numbers.
When you edit, state plainly: which rows changed, what the values were before and after,
which file the user should load, and where their backup is. If a query returned nothing,
say so rather than filling the gap with plausible-looking PCM knowledge; an empty result
usually means the column or table is named differently in that game year, and the fix is to
go look at the schema again.



### TODO CONSTRAINT
Two constraints worth remembering so you don't waste a call: rating values are bounded
55–85, and `mediumMountain` / `currentAbility` don't exist on older saves (they come back
`null`, and setting `mediumMountain` is rejected there).