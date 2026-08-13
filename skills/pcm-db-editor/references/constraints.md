# Database value constraints

Read this **before writing any `UPDATE`, `INSERT`**. `pcm-schema.md`
tells you where the data lives; this file tells you what you're allowed to put in it. A
value that's valid SQL can still be rejected by the write tool, silently clamped, or produce
a `.cdb` the game refuses to load — and you only find that out after a full round trip.

This list records what has actually been observed on official databases, not what Pro cycling manager's documentation
claims.

## Value ranges

| Table         | Column       | Constraint                  |
| ------------- | ------------ | --------------------------- |
| `DYN_cyclist` | `charac_i_*` | Integer **50–85**           |
| `DYN_cyclist` | `limit_i_*`  | Either **`0`** or **60–84** |

The game's own editor can't produce `charac_i_*` values outside the 50–85 band. Raw SQL writes
them happily; expect the game to clamp or misbehave. `limit_i_*` values are potential ceilings,
not abilities — see below; forcing them into the 50–85 band is wrong.

### The 50–85 band applies to abilities only

Every ability column is `charac_i_<terrain>` — `charac_i_plain`, `charac_i_sprint`,
`charac_i_mountain`, `charac_i_medium_mountain`, and so on. 50 and 85 are hard game bounds:
you cannot go below 50 or above 85 in-game.

Each ability has a **twin `limit_i_<terrain>` column** holding that rider's potential ceiling
for the stat. These follow completely different rules, and the distribution is bimodal: a
limit is either **`0`** or a value in **60–84**. Nothing in between, and never below 60 — so
the band is narrower than the 50–85 ability range and doesn't line up with it.

## Columns whose names are not what the tools call them

The pcm-mcp rating parameters are **camelCase API names, not database columns**. Grepping the
schema for the API name finds nothing and makes a column that exists look absent:

| pcm-mcp parameter  | Actual `DYN_cyclist` column                              |
| ------------------ | -------------------------------------------------------- |
| `mediumMountain`   | `charac_i_medium_mountain` (+ `limit_i_medium_mountain`)  |
| `currentAbility`   | `value_f_current_ability`                                |
| every other rating | `charac_i_<terrain>`                                     |

So search on the real prefix, not the API name:

```bash
sqlite3 save.sqlite "SELECT name, type FROM pragma_table_info('DYN_cyclist') WHERE name LIKE '%mountain%';"
```

Nothing back means the column really isn't there — say so rather than writing an `UPDATE`
that matches zero rows and looks like success.

One more trap: `value_f_current_ability` is `0.0` for **all** riders on the official
release — the game computes it at runtime rather than storing it. Reporting it as a rider's
current form gives the user a wall of zeros. Derive from the individual `charac_i_*` values
instead. Note also that `value_f_potentiel` is a 0.5–6.0 star rating, *not* an ability on the
50–85 scale; the two are easy to confuse.

## Format-level rules

These apply to every database regardless of game year — they come from how the CDB container
works, not from any particular column. SKILL.md carries a two-line summary of the first two
because they're the ones that destroy a file; this section is the full version.

- **Data only, never structure.** No `CREATE` / `ALTER` / `DROP`. Each column's CDB data type
  and column index live inside its _declared type string_ in the SQLite schema (see below), so
  a table or column you create by hand has no valid metadata and the reverse conversion can't
  encode it.
- **Never touch `DB_STRUCTURE`.** It isn't a game table — it carries per-table CDB flags whose
  meaning is undocumented but which the writer needs. Editing or dropping it breaks the
  round trip.
- **New rows need a free ID and resolvable foreign keys.** `SELECT MAX(IDx) + 1 FROM <table>`
  for the key, and verify every `fkID*` points at a row that exists. Orphaned FKs don't block
  conversion — foreign keys aren't enforced — but they produce odd behaviour in-game, which is
  much harder to diagnose than a conversion error.

### Reading a column's real CDB type

Declared types look like `INTEGER 45604`, `TEXT 45074`, `REAL 47633`. The number is not
decoration — it packs the table id, the column index and the CDB data type:

```
encoded = (tableId * 256 + columnIndex) * 16 + dataType
```

So the data type is the **low 4 bits**, `encoded & 15`:

| Value | CDB type        | Storage range              |
| ----- | --------------- | -------------------------- |
| 0     | `INTEGER`       | 32-bit signed              |
| 1     | `FLOAT`         | 32-bit float               |
| 2     | `STRING`        | text                       |
| 3     | `BOOLEAN`       | bit-packed, 0/1            |
| 4     | `INTEGER_BYTE`  | **signed −128…127**        |
| 5     | `INTEGER_SHORT` | **signed −32768…32767**    |
| 10    | `FLOAT_LIST`    | text-encoded list          |
| 11    | `INTEGER_LIST`  | text-encoded list          |

The narrow integer types are the ones that bite, so check before writing a large value:

```sql
SELECT name, type, CAST(substr(type, instr(type,' ')+1) AS INTEGER) % 16 AS cdb_type
FROM pragma_table_info('DYN_cyclist') WHERE name = 'charac_i_plain';
-- INTEGER 45604 -> 4 -> INTEGER_BYTE, so this column tops out at 127
```

SQLite stores an out-of-range value happily; the CDB writer then truncates it to the byte or
short width, so 300 in a byte column comes back as 44. There is no error — just wrong data in
the rebuilt database, which is why verifying after the round trip matters.

Don't go looking for the literal strings `INTEGER_BYTE` or `INTEGER_SHORT` in the schema —
they never appear there. Only the encoded number does.
