# PCM database schema — conventions and recipes

Read this when you're past a single-table `SELECT`. It covers the naming conventions PCM
follows, how to discover a save's actual schema in a few queries, and worked examples for
the questions people usually ask.

**Important:** column names drift between PCM releases (2014 → 2026 all use the same
container format but not the same columns). The conventions below are stable; individual
column names are not. Every recipe here starts from discovery — run the discovery queries,
then write the real query. Don't paste a column name from memory into a `WHERE` clause.

## Contents

- [Naming conventions](#naming-conventions)
- [Discovering a save in four queries](#discovering-a-save-in-four-queries)
- [The tables that answer most questions](#the-tables-that-answer-most-questions)
- [Recipes](#recipes)
- [Editing safely](#editing-safely)

## Naming conventions

| Pattern                           | Meaning                                                                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `STA_*`                           | **Static** reference data — the game's catalogue: race definitions, countries, rider types, jersey data. Shared by every career.  |
| `DYN_*`                           | **Dynamic** career data — the state of _this_ save: cyclists, teams, contracts, results. This is what you edit.                   |
| `IDxxx`                           | Primary key of table `xxx` (`IDcyclist` in `DYN_cyclist`, `IDteam` in `DYN_team`).                                                |
| `fkIDxxx`                         | Foreign key pointing at `xxx.IDxxx` (`DYN_cyclist.fkIDteam` → `DYN_team.IDteam`).                                                 |
| `gene_sz_*`                       | A general string field — `gene_sz_name` is the usual display name, `gene_sz_filename` a file stem. `sz` = zero-terminated string. |
| `gene_i_*`, `charac_i_*`, `*_i_*` | Integer fields. The segment after the prefix names the attribute.                                                                 |
| `DB_STRUCTURE`                    | Not a game table — converter metadata (per-table CDB flags). Never edit or drop it.                                               |

Converting with `--normalize` turns the `IDxxx` / `fkIDxxx` convention into real
`PRIMARY KEY` / `FOREIGN KEY` constraints, which means `PRAGMA foreign_key_list(...)` will
tell you how a table connects to the rest. That's the fastest way to map an unfamiliar save.

## Discovering a save in four queries

```sql
-- 1. What's in here, biggest tables first? (dynamic career data)
SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'DYN%' ORDER BY name;

-- 2. What does this table hold?
PRAGMA table_info(DYN_cyclist);

-- 3. What does it point at? (requires --normalize)
PRAGMA foreign_key_list(DYN_cyclist);

-- 4. Where is the column I want? Search by keyword across a table.
SELECT name, type FROM pragma_table_info('DYN_cyclist') WHERE name LIKE '%name%';
```

Query 4 is the workhorse: swap `%name%` for `%mountain%`, `%birth%`, `%wage%`, `%date%`
and you'll find the right column in one shot instead of guessing.

To find which table a concept lives in at all:

```sql
SELECT m.name AS tbl, p.name AS col
FROM sqlite_master m JOIN pragma_table_info(m.name) p
WHERE m.type='table' AND p.name LIKE '%sprint%';
```

Then confirm with a few rows: `SELECT * FROM DYN_cyclist LIMIT 3;` — seeing real values
tells you more about a column than its name does (is that date an integer day count? is
that rating on a 0–100 scale?).

## The tables that answer most questions

These names are stable across releases; their _columns_ still need checking.

| Table                                | Holds                                                                                                                                      |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `DYN_cyclist`                        | Every rider in the career: names, birth date, nationality FK, and the per-terrain ability ratings. Keyed by `IDcyclist`.                   |
| `DYN_team`                           | Teams: name, short name, division FK, country FK, evaluation, manager. Keyed by `IDteam`.                                                  |
| `DYN_contract_cyclist`               | The rider ↔ team link: which team, wage, market value, start/end year. A rider can have several rows over time — filter to the active one. |
| `STA_type_rider`                     | Rider archetypes (sprinter, climber, puncheur…) referenced from cyclists.                                                                  |
| `STA_race`                           | Race definitions, including `gene_sz_filename` (the stem PCM uses for startlist XML, e.g. `c0_almeria`). Keyed by `IDrace`.                |
| `DYN_player` / player-related tables | The human player's login and their team — the entry point for "my team".                                                                   |

Ratings exposed by pcm-mcp, so present in some form on every save: plain, mountain,
downhilling, cobble, time trial, prologue, sprint, acceleration, endurance, resistance,
recuperation, hill, baroudeur — plus `mediumMountain` and `currentAbility` on newer saves
only. Values sit in the 55–85 band for meaningful riders. Find their real column names with
the keyword query above before writing an `UPDATE`.

## Recipes

Each of these is a _shape_, not a literal query — fill in the column names you discovered.

### A team's roster with ratings

The join that matters: cyclist → active contract → team, plus rider type for readability.

```sql
SELECT c.IDcyclist, c.<lastname>, c.<firstname>, t.gene_sz_name AS team,
       rt.gene_sz_name AS type, c.<mountain>, c.<sprint>, c.<timetrial>
FROM DYN_cyclist c
JOIN DYN_contract_cyclist ct ON ct.fkIDcyclist = c.IDcyclist
JOIN DYN_team t             ON t.IDteam = ct.fkIDteam
LEFT JOIN STA_type_rider rt ON rt.IDtype_rider = c.fkIDtype_rider
WHERE t.gene_sz_name LIKE '%<team>%'
ORDER BY c.<ability> DESC;
```

If you get duplicate riders, the contract filter is missing — inspect
`PRAGMA table_info(DYN_contract_cyclist)` for the year/active columns and constrain to the
current season.

### Find a rider

```sql
SELECT IDcyclist, <firstname>, <lastname>, <birthdate>
FROM DYN_cyclist
WHERE <lastname> LIKE '%pogac%' COLLATE NOCASE;
```

Always resolve to `IDcyclist` first, then use the ID everywhere else — names are not unique
and PCM stores accented characters that are painful to match on.

### Free agents

Riders with no active contract row — useful for transfer questions:

```sql
SELECT c.IDcyclist, c.<lastname>
FROM DYN_cyclist c
LEFT JOIN DYN_contract_cyclist ct ON ct.fkIDcyclist = c.IDcyclist AND <active condition>
WHERE ct.fkIDcyclist IS NULL;
```

### Resolving codes to names

Anything ending in an FK is a code; join to its `STA_` table to get text. Country,
division and rider type all work this way. If a value looks like a bare integer in your
output, you probably skipped a join.

### Startlists

`pcm_generate_startlist_xml` (Route A) builds a PCM-ready startlist from team + cyclist IDs
and derives the file name from `STA_race.gene_sz_filename`. On Route B, look the race up in
`STA_race` by name to get its `IDrace` and filename stem, then gather the rosters with the
roster query above.

## Editing safely

```sql
-- 1. See exactly what you're about to hit.
SELECT IDcyclist, <col> FROM DYN_cyclist WHERE IDcyclist = 1234;

-- 2. Change it.
UPDATE DYN_cyclist SET <col> = 78 WHERE IDcyclist = 1234;

-- 3. Confirm the row count and the new value.
SELECT changes();
SELECT IDcyclist, <col> FROM DYN_cyclist WHERE IDcyclist = 1234;
```

Rules that keep the file loadable in-game:

- **Data only, never structure.** No `CREATE` / `ALTER` / `DROP`: the CDB type and column
  index of each column live inside its declared type string, so hand-made tables and columns
  have no valid metadata and the reverse conversion can't encode them.
- **Stay inside the column's range.** An `INTEGER_BYTE` column holds −128…127, an
  `INTEGER_SHORT` 0…65535. SQLite will happily store an out-of-range value that the CDB
  writer then can't represent.
- **Never key an `UPDATE` on a name** when an ID is available — a `LIKE` that matches two
  riders silently edits both.
- **New rows:** `SELECT MAX(IDx) + 1 FROM <table>` for the key, and verify every `fkID*`
  resolves. Orphaned FKs don't block conversion (foreign keys aren't enforced) but they do
  produce odd behaviour in-game.
- **Bulk edits deserve a dry run.** Run the `SELECT` form of the `WHERE` clause first and
  look at the count — "I meant to buff one rider, not 340" is a much better discovery before
  the write than after.
