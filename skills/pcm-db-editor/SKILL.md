---
name: pcm-db-editor
description: Open, explore and edit Pro Cycling Manager databases (.cdb) — rider ratings, team rosters, contracts, races. Routes between the pcm-mcp MCP server and a cdb → SQLite conversion via the cdb-converter CLI. Use this skill whenever a .cdb file is mentioned, or whenever someone talks about a PCM / Pro Cycling Manager save, career, database, roster, cyclist stats, or wants to "edit my game" — even if they never say the words "cdb" or "database", and even if they only want to read something rather than change it.
---

# Pro Cycling Manager database editing

Pro Cycling Manager stores everything — cyclists, teams, contracts, races, the whole game
database — in a binary `.cdb` file. It is not readable as-is, but it is _exactly_ a SQLite
database wearing a costume: a lossless conversion exists in both directions. Once you know
that, every PCM question becomes an ordinary SQL question.

Your job is to pick the right door into that database, answer the question with real data
(never from memory about how PCM "usually" works), and — if the user wants changes — write
them back without ever putting the original at risk.

Two words are used precisely throughout this skill. A **database** is a `.cdb` file — it may
be a player save, an official release or a community update, and nothing downstream cares
which. A **save** is narrower: a `.cdb` the game itself wrote as the player played, found
under a PCM edition's `Cloud/` folder. Say "save" only when that distinction matters.

## Which door to use

There are two routes, and one question settles the choice: **are the `pcm_*` tools in your
tool list?** Look; don't assume.

- **Absent** → Route B. This is the common case. Say so once, then carry on — don't try to
  install anything and don't block on it.
- **Present** → Route A for lookups and one-off edits, falling back to Route B as soon as the
  question outgrows the tools.

The tools decide it because of what each route can physically reach. pcm-mcp runs on the
user's machine, so it can find the game's own save directories, discover careers, and write a
new `.cdb` there — but it cannot see a file that exists only in your sandbox. Route B works
anywhere you can read the file and run the converter, and gives you unrestricted SQL:
JOINs, aggregates and bulk edits the MCP tools don't expose.

Two consequences worth holding onto. If the `.cdb` was uploaded into the conversation or sits
in your working directory, Route B is the only option no matter which tools you have. And if
you're on Route A facing multi-table analysis, schema exploration, or edits across dozens of
rows, say so and fall back to Route B on a copy — that's a normal escalation, not a failure.

When Route A is available, let `pcm_list_saves` find the careers rather than guessing at
install locations — it knows where this platform and game year put them. If it returns
nothing, ask the user for the path instead of hunting through directories yourself.

## The one rule that matters: never damage the original

The database in front of you may be irreplaceable — a save can represent hundreds of hours of
career, and a hand-tuned community update is no easier to rebuild. Treat the original `.cdb`
as read-only, always:

- **Back it up before touching anything.** `cp database.cdb database_backup.cdb` costs nothing.
- **Write edits to a new file**, e.g. `database_edited.cdb` next to the original. The MCP write
  tools enforce this (they refuse to overwrite); on Route B _you_ enforce it.
- **Watch the CLI's default output path.** `npx cdb-converter database.sqlite` writes to
  `database.cdb` — which is very plausibly the user's original. Always pass an explicit output
  path on the way back.
- Tell the user to load the edited database in-game and verify before deleting anything.

Before writing anything — either route — read `references/database-constraints.md`. It's the running
list of what the game and the write tools actually accept.

## Route A — pcm-mcp

Every `pcm_*` tool is stateless: it takes an absolute `databasePath`, re-reads the `.cdb`
into a fresh in-memory database, and answers. There's no implicitly current file, so carry
the path through the conversation yourself.

Typical flow:

1. **Locate** — `pcm_list_saves` to discover careers, or `pcm_validate_database <absolute path>`
   when the user already gave you a file.
2. **Explore** — `pcm_list_tables` / `pcm_get_table_schema` to learn the shape,
   `pcm_search_cyclist`, `pcm_search_team`, `pcm_get_team_roster`, `pcm_get_player_info`
   for the common questions, `pcm_query_database` for anything else (read-only `SELECT` /
   `WITH … SELECT`, capped at 1000 rows).
3. **Edit** — `pcm_update_cyclist_ratings` for a rider's abilities, `pcm_update_database` for a
   single `INSERT`/`UPDATE`/`DELETE`. Both write to a new `outputPath` and refuse to
   overwrite. DDL and stacked statements are rejected.

When a user wants several edits at once, note that `pcm_update_database` applies one statement
per call and each call produces a new file. Chaining three edits means three files. Past
two or three changes, Route B is cleaner: do it all in SQLite, convert once.

## Route B — convert to SQLite, edit, convert back

The `cdb-converter` package does a **lossless** round trip: tables, column order,
data types and internal flags all survive `cdb → sqlite → cdb`, so the game reads the result
happily.

Lossless means the _data_ is preserved, not the bytes. A round-tripped file has a different
checksum and is typically ~10% smaller than the original (compression differs), which looks
alarming if you're checksum-comparing. Verify by querying the rebuilt file, as below — never
by comparing file size or hash.

### Open

```bash
cp database.cdb database_backup.cdb                   # backup first, always — keep .cdb
npx -y cdb-converter database.cdb database.sqlite --normalize
```

`--normalize` reconstructs `PRIMARY KEY` / `FOREIGN KEY` constraints from PCM's naming
conventions. Use it by default: it makes the database self-describing, so you can discover
how tables relate instead of guessing, and it's round-trip safe. Costs ~10% time and ~40% size.

Add `--index-fk` only if you're running heavy JOINs on a big database — it roughly doubles the size.

`scripts/open_cdb.sh` bundles the backup, the conversion and a first inventory of tables by
row count — a good starting point when you don't know the database yet.

### Explore

Use the `sqlite3` CLI (or any SQLite library). Discover before querying — PCM's schema
varies across game years, so confirm names rather than trusting recall:

```bash
sqlite3 database.sqlite ".tables"
sqlite3 database.sqlite "PRAGMA table_info(DYN_cyclist);"
sqlite3 -header -column database.sqlite "SELECT ... LIMIT 20;"
```

Read `references/pcm-schema.md` for the naming conventions (`DYN_` vs `STA_`, `IDx` /
`fkIDx`, the `gene_sz_` prefix), the tables that answer most questions, and ready-made
queries for rosters, ratings, contracts and free agents. Read it as soon as you're writing
anything beyond a single-table `SELECT` — it will save you a round of trial and error.

### Edit and write back

```bash
sqlite3 database.sqlite "UPDATE DYN_cyclist SET ... WHERE IDcyclist = 1234;"
npx -y cdb-converter database.sqlite database_edited.cdb   # explicit output path!
```

Two things break the round trip irrecoverably, so keep them in mind even without opening a
reference file: **no DDL** (`CREATE` / `ALTER` / `DROP` — a column's CDB type and index are
encoded in its declared type string, so hand-made structure has no valid metadata and can't
be converted back), and **never edit or drop `DB_STRUCTURE`** (converter metadata the game
needs). Everything else — value ranges, column types, IDs and foreign keys for new rows — is
in `references/database-constraints.md`, which you should have read before writing anyway.

Then verify what you changed before handing it back — re-open the produced `.cdb` and
`SELECT` the rows you touched:

```bash
npx -y cdb-converter database_edited.cdb verify.sqlite
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
