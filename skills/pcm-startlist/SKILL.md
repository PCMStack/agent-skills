---
name: pcm-startlist
description: >-
  Build a Pro Cycling Manager (PCM) race startlist and export it as the .xml
  file PCM imports. Use when the user wants to create, compose, or generate a
  startlist for a PCM race — picking which teams take part and which riders
  each team brings. Orchestrates the read-only PCM MCP tools (pcm_query_database,
  pcm_search_cyclist) to gather data and pcm_generate_startlist_xml to produce
  the file. Triggers on phrases like "startlist", "liste de départ",
  "engagés pour la course", "génère le fichier xml de la course X".
---

# PCM startlist builder

Compose a startlist for a Pro Cycling Manager race and write the `.xml` file PCM
imports. This skill owns the _workflow_ (find the race, choose teams, choose
riders); the deterministic serialization is delegated to the
`pcm_generate_startlist_xml` MCP tool — never hand-write the XML.

## Output format (for reference only — the tool emits this)

```xml
<startlist>
    <team id="34">
        <cyclist id="7602" />
        <cyclist id="5996" />
    </team>
</startlist>
```

`<team id>` = `DYN_team.IDteam`, `<cyclist id>` = `DYN_cyclist.IDcyclist`. The file
name is `STA_race.gene_sz_filename` + `.xml` (e.g. `c0_almeria.xml`) and is
returned by the tool — don't invent it.

## Workflow

### 1. Get a database path

Every step reads a `.cdb` database — a player save, an official release or a
community update, it makes no difference. If the user hasn't given an absolute
`databasePath`:

- Try `pcm_list_saves` to find their saves (Windows only — fails on
  macOS/Linux Wine/Proton prefixes).
- Otherwise ask the user for the absolute `.cdb` path. Keep it in context; the
  tools are stateless and need it on every call.

### 2. Identify the race (get `IDrace`)

The user names a race; resolve it to an `IDrace` with `pcm_query_database`:

```sql
SELECT IDrace, gene_sz_race_name, gene_sz_filename
FROM STA_race
WHERE gene_sz_race_name LIKE '%almeria%';
```

If several match, show the candidates (name + id) and let the user pick. Confirm
the `gene_sz_filename` so the user knows the output file name up front.

### 3. Decide which teams take part

Either the user supplies the teams, or you propose them. Resolve names to
`IDteam`:

```sql
SELECT IDteam, gene_sz_name, gene_sz_shortname FROM DYN_team
WHERE gene_sz_name LIKE '%ineos%';
```

A typical startlist has ~18–25 teams. If the user just says "the usual teams",
ask which division/tier or list candidates rather than guessing.

### 4. Pick riders per team

A team's full squad is the candidate pool — a startlist usually brings **7** of
them (the count is free; the example pack mixes 6 and 7). Get a team's roster:

```sql
SELECT IDcyclist, gene_sz_firstname, gene_sz_lastname
FROM DYN_cyclist
WHERE fkIDteam = 34;
```

To pick riders that fit the race profile, pull the ratings too (the
`charac_i_*` columns — see `pcm_search_cyclist`, which already surfaces them) and
favour the relevant specialty: sprinters/`charac_i_sprint` for flat finishes,
`charac_i_mountain` for climbs, `charac_i_cobble` for cobbled classics, etc. If
the user has preferences (leaders, exclusions), apply them. Confirm the selection
before generating when there's any ambiguity.

### 5. Generate the file

Call `pcm_generate_startlist_xml` with `databasePath`, `raceId`, and `teams`:

```json
{
  "databasePath": "/abs/path/OfficialRelease.cdb",
  "raceId": 128,
  "teams": [
    { "id": 34, "cyclists": [7602, 5996, 1381, 3291, 6342, 3912, 5613] },
    { "id": 25, "cyclists": [6346, 8702, 17152, 15300, 7048, 6433, 15398] }
  ]
}
```

The tool returns `{ fileName, xml }`. If a team has no riders or `teams` is empty
the tool errors — fix the selection and retry.

### 6. Deliver

Present the returned `fileName` and `xml`. Offer to write it to disk (e.g. the
user's PCM `Startlists`/race-import folder or the working directory) — the MCP
server is read-only and does not write files, so saving is done outside it.

## Notes

- All PCM MCP tools used here are read-only; this workflow never modifies the
  database.
- IDs, not names, go into the XML — always resolve names to `IDteam`/`IDcyclist`
  via the queries above before calling the tool.
