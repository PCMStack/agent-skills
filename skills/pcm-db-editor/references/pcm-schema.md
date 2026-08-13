# Database schema

Read this when you're past a single-table `SELECT`. It covers the naming conventions Pro cycling manager
follows, how to discover a database's actual schema in a few queries, and worked examples for
the questions people usually ask.


## Contents

- [Naming conventions](#naming-conventions)
- [Discovering a database in four queries](#discovering-a-database-in-four-queries)
- [The tables that answer most questions](#the-tables-that-answer-most-questions)
- [Rider ratings](#rider-ratings)
- [Recipes](#recipes)
- [Editing safely](#editing-safely)

## Naming conventions

### Table prefixes

| Pattern        | Meaning                                                                                                                          |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `STA_*`        | **Static** reference data — the game's catalogue: race definitions, countries, rider types, jersey data. Shared by every database.  |
| `DYN_*`        | **Dynamic** data — the state of _this_ database: cyclists, teams, contracts, results. This is what you edit.                   |
| `GAM_*`        | **Game/session** state — the human player's account, save metadata, rewards. Small, mostly meaningful in a save, but this is where "my team" resolves. |
| `INF_*`        | Infrastructure/preset tables. Rarely edited.                                                                                                                          |

### Column names

| Pattern                           | Meaning                                                                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `IDxxx`                           | Primary key of table `xxx` (`IDcyclist` in `DYN_cyclist`, `IDteam` in `DYN_team`).                                                |
| `fkIDxxx`                         | Foreign key pointing at `xxx.IDxxx` (`DYN_cyclist.fkIDteam` → `DYN_team.IDteam`).                                                 |
| `gene_sz_*`                       | A general string field — `gene_sz_name` is the usual display name, `gene_sz_filename` a file stem. `sz` = zero-terminated string. |
| `gene_strID_*`                    | A **localization key**, not display text. `STA_type_rider.gene_strID_name` is a token the game resolves to a translated label.    |
| `charac_i_*`                      | A rider's **current ability** for one terrain. The 50–85 stats people mean by "ratings".                                          |
| `limit_i_*`                       | The **potential ceiling** twin of the `charac_i_*` with the same suffix. Different scale — see [Rider ratings](#rider-ratings).   |
| `gene_i_*`, `value_i_*`, `*_i_*`  | Integer fields. `value_f_*` / `gene_f_*` are floats, `gene_b_*` booleans, `*_ilist_*` text-encoded integer lists.                 |

On Route B, converting with `cdb-converter --normalize` turns the `IDxxx` / `fkIDxxx` convention into real
`PRIMARY KEY` / `FOREIGN KEY` constraints, which means `PRAGMA foreign_key_list(...)` will
tell you how a table connects to the rest. That's the fastest way to map an unfamiliar database.

## Discovering a database in four queries

```sql
-- 1. What's in here? 
SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'DYN%' ORDER BY name;

-- 2. What does this table hold?
PRAGMA table_info(DYN_cyclist);

-- 3. What does it point at? (requires a cdb-converter --normalize conversion)
PRAGMA foreign_key_list(DYN_cyclist);

-- 4. Where is the column I want? Search by keyword across a table.
SELECT name, type FROM pragma_table_info('DYN_cyclist') WHERE name LIKE '%mountain%';
```

Query 4 is the workhorse: swap `%mountain%` for `%sprint%`, `%birth%`, `%wage%`, `%date%`
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

| Table                  | Holds                                                                                                                          |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `DYN_cyclist`          | Every rider: `gene_sz_lastname`, `gene_sz_firstname`, `gene_i_birthdate`, `fkIDteam`, `fkIDtype_rider`, and the ability columns. Keyed by `IDcyclist`. |
| `DYN_team`             | Teams: `gene_sz_name`, `gene_sz_shortname`, `fkIDdivision`, `fkIDcountry`, `value_f_current_evaluation`, `value_i_budget`. Keyed by `IDteam`. |
| `DYN_contract_cyclist` | Rider ↔ team link: `fkIDcyclist`, `fkIDteam`, `finan_i_period_wage`, `iYearBegin`, `iYearEnd`, `iRole`, and `gene_b_active_contract` — the flag that picks the current one. |
| `STA_type_rider`       | Rider archetypes (sprinter, climber, puncheur…). Labels are in `gene_strID_name`, a localization key rather than plain text.     |
| `STA_race`             | Race definitions, including `gene_sz_filename`. Keyed by `IDrace`.      |
| `GAM_user`             | The human player: `game_sz_login`, `game_sz_display_name`, `fkIDteam_duplicate`, `fkIDcyclist`. **The entry point for "my team".** |
| `GAM_career_data`      | Career-level key/value metadata (`UID` / `value`).                                                                              |


## Rider ratings

Every terrain has a **pair** of columns, and confusing them is the most common way to get
this wrong:

- `charac_i_<terrain>` — the rider's current ability. This is what people mean by "ratings".
- `limit_i_<terrain>` — the potential ceiling for that ability.

The terrains: `plain`, `mountain`, `medium_mountain`, `downhilling`, `cobble`,
`timetrial`, `prologue`, `sprint`, `acceleration`, `endurance`, `resistance`, `recuperation`,
`hill`, `baroudeur`.

Two nearby columns that look like ratings but aren't:

- `value_f_potentiel` — a 0.5–6.0 **star rating**, not an ability.
- `value_f_current_ability` — `0.0` for every rider the game
  computes it at runtime. Don't report it. Derive from the `charac_i_*` values instead.

Value ranges, what happens if you exceed them, and the ability-vs-limit trap are covered in
`constraints.md` — read it before writing any of these.

## Recipes

### A team's roster with ratings

**Resolve the team to an `IDteam` first.** A `LIKE` on the name quietly picks up development
squads — `'%Soudal%'` matches both `Soudal - QuickStep` (id 10) and
`Soudal - Quick-Step Devo Team` (id 210), so the roster comes back 47 riders instead of 30:

```sql
SELECT IDteam, gene_sz_name FROM DYN_team WHERE gene_sz_name LIKE '%Soudal%';
```

Then join on `DYN_cyclist.fkIDteam`, which is the membership link:

```sql
SELECT c.IDcyclist, c.gene_sz_lastname, c.gene_sz_firstname,
       c.charac_i_sprint, c.charac_i_mountain, c.charac_i_timetrial
FROM DYN_cyclist c
WHERE c.fkIDteam = 10
ORDER BY c.charac_i_sprint DESC;
```

Prefer `fkIDteam` over `DYN_contract_cyclist` for "who rides for this team". Every rider
carries an `fkIDteam`, but only a fraction of the database has a contract row — often well
under a quarter of the field — so the contract join silently drops most riders. Compare
`COUNT(*)` on both tables if you need the exact split for a given database. Bring contracts in
when the question is about **terms** — wage, duration, role:

```sql
SELECT c.gene_sz_lastname, ct.finan_i_period_wage, ct.iYearBegin, ct.iYearEnd, ct.iRole
FROM DYN_cyclist c
JOIN DYN_contract_cyclist ct ON ct.fkIDcyclist = c.IDcyclist
WHERE c.fkIDteam = 10 AND ct.gene_b_active_contract = 1;
```

If riders appear twice, the `gene_b_active_contract` filter is missing — a rider accumulates
a contract row per spell, so the join multiplies without it.

Joining `STA_type_rider` for the archetype gives you `gene_strID_name`, a localization token
rather than a readable label. Report the rider's actual stats instead of a raw token.

### Find a rider

**Accents break the obvious query.** Game database stores real diacritics, and SQLite's `NOCASE`
collation only folds ASCII — so `LIKE '%pogac%' COLLATE NOCASE` returns **zero rows** for a
rider stored as `Pogačar`. Match on the unaccented prefix instead:

```sql
SELECT IDcyclist, gene_sz_firstname, gene_sz_lastname, gene_i_birthdate
FROM DYN_cyclist
WHERE gene_sz_lastname LIKE '%Pog%';
-- 6777 | Tadej | Pogačar
```

Keep the fragment short and ASCII-only, stopping before the first accented character. If a
search for a rider you're certain exists comes back empty, assume an accent before assuming
the rider is absent. Always resolve to `IDcyclist` first, then use the ID everywhere else —
names aren't unique either.

### Free agents

Unsigned riders sit on a **placeholder team** rather than having no team — usually the team
named `-`, which holds a large slice of the database. Its `IDteam` changes between databases,
so find the sentinel, don't hardcode it:

```sql
SELECT IDteam FROM DYN_team WHERE gene_sz_name = '-';

SELECT c.IDcyclist, c.gene_sz_lastname, c.charac_i_plain
FROM DYN_cyclist c WHERE c.fkIDteam = <the ID you just resolved>
ORDER BY c.charac_i_plain DESC;
```

Defining free agents as "no active contract row" instead returns far more riders, most of
them on real teams — the contract table just doesn't cover them.

### The player's own team

`GAM_user` holds the human player, linking to their team and avatar rider:

```sql
SELECT u.game_sz_display_name, t.gene_sz_name
FROM GAM_user u JOIN DYN_team t ON t.IDteam = u.fkIDteam_duplicate
WHERE u.game_i_active = 1;
```

### Resolving codes to names

Anything ending in an FK is a code; join to its `STA_` table to get text. Country,
division and rider type all work this way. If a value looks like a bare integer in your
output, you probably skipped a join.

## Editing safely

```sql
-- 1. See exactly what you're about to hit — ability and its ceiling together.
SELECT IDcyclist, gene_sz_lastname, charac_i_sprint, limit_i_sprint
FROM DYN_cyclist WHERE IDcyclist = 5979;

-- 2. Change it.
UPDATE DYN_cyclist SET charac_i_sprint = 84 WHERE IDcyclist = 5979;

-- 3. Confirm the row count and the new value.
SELECT changes();
SELECT IDcyclist, charac_i_sprint FROM DYN_cyclist WHERE IDcyclist = 5979;
```

Whether a given _value_ is acceptable — the 50–85 band, the `limit_i_*` distinction, narrow
integer column widths, what breaks the round trip — is in `constraints.md`. Read it before
step 2. What follows is about writing the statement itself:

- **Never key an `UPDATE` on a name** when an ID is available — a `LIKE` that matches two
  riders silently edits both, and you won't notice until the user does.
- **Bulk edits deserve a dry run.** Run the `SELECT` form of the `WHERE` clause first and look
  at the count — "I meant to buff one rider, not 340" is a much better discovery before the
  write than after.
- **`SELECT changes()` after every write.** Zero rows changed means the `WHERE` matched
  nothing, usually a column named differently in this game year — a failure that otherwise
  looks exactly like success.
