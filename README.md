<div align="center">
  <img src="plugins/pcm/assets/logo.svg" alt="PCMStack" width="96">

# PCMStack Agent Skills

Read and edit any Pro Cycling Manager database by asking an AI assistant: rosters, startlists, rider ratings changed in plain language.

[Install](#install) · [Skills](#whats-inside) · [How it works](#how-it-works) · [Development](#development)

</div>

> [!NOTE]
> Unofficial community project. Not affiliated with, endorsed by, or supported by Cyanide
> Studio or Nacon.

Pro Cycling Manager keeps the entire game world — riders, teams, contracts, races — in a
binary `.cdb` file. It is not readable as-is, but it is a SQLite database in disguise, and the
conversion is lossless in both directions. This repository packages that knowledge as
[Agent Skills](https://agentskills.io/): instructions and scripts that teach an AI coding
agent how to open a PCM database, answer questions from real data, and write changes back
without ever putting your save at risk.

```
You  ▸ Who are my three best climbers, and how old are they?
You  ▸ Bump Pogačar's descending to 80 in a copy of my save
You  ▸ Build the startlist for Almería — 20 teams, sprinters up front
```

## Install

The repository is a marketplace containing a single plugin, `pcm`. In **Claude Code**:

```
/plugin marketplace add PCMStack/agent-skills
/plugin install pcm@pcmstack
```

Then just ask. Skills trigger on their own when a request matches — no command to remember.

<details>
<summary>Other agents</summary>

The skills follow the portable `SKILL.md` format, so any agent that reads Agent Skills can
use them. Point your agent at `plugins/pcm/skills/`, or clone the repository and add it as a
local marketplace:

```
/plugin marketplace add /path/to/agent-skills
```

Codex-compatible manifests live in `.agents/plugins/marketplace.json` and
`plugins/pcm/.codex-plugin/plugin.json`.

</details>

### Requirements

| Requirement | Why                                                               |
| ----------- | ----------------------------------------------------------------- |
| Node 22+    | Runs `cdb-converter` via `npx` for the `.cdb` ⇄ SQLite conversion |
| `sqlite3`   | Querying and editing the converted database                       |
| A `.cdb`    | A career save, an official release, or a community update         |

Node and `sqlite3` are only needed at runtime, when a skill actually opens a database.

## What's inside

### `pcm-database`

Open, explore and edit a PCM database. The skill picks between two routes on its own:

- **pcm-mcp** — the bundled [MCP server](https://github.com/PCMStack/mcp) discovers your saves
  on disk and exposes targeted tools (search a cyclist, read a roster, update ratings). Best
  for lookups and one-off edits.
- **SQLite** — a lossless `.cdb → sqlite` conversion via
  [cdb-converter](https://github.com/PCMStack/converter), giving unrestricted SQL: JOINs,
  aggregates, bulk edits. The only option for a file the agent has locally, and the right one
  for anything analytical.

It ships `scripts/open-cdb.sh` (backup + convert + table inventory in one step) and two
reference documents the agent loads on demand: the schema naming conventions with ready-made
queries, and the constraints that must hold for the game to accept an edited database.

### `pcm-startlist`

Compose a race startlist — which teams take part, which riders each brings — and export the
`.xml` file PCM imports. The skill resolves the race and the rosters from your database, picks
riders that fit the profile (sprinters for flat finishes, climbers for mountains), and
delegates serialization to `pcm_generate_startlist_xml` so the file is always well-formed.

## How it works

```
your request ──▶ agent ──▶ SKILL.md
                            │
                            ├─▶ pcm-mcp (MCP)  ──▶ saves on disk, targeted reads/writes
                            └─▶ cdb-converter  ──▶ database.sqlite ──▶ SQL ──▶ database_edited.cdb
```

> [!IMPORTANT]
> A career save can represent hundreds of hours. Every skill and script here treats the
> original `.cdb` as **read-only**: it is backed up first, edits are written to a _new_ file,
> and nothing is ever overwritten in place. Load the edited database in-game and verify it
> before deleting your backup.

## Development

There is no build step and no application code — the deliverables are Markdown and JSON
manifests, read by another agent at runtime.

```
.claude-plugin/marketplace.json    # Claude Code marketplace
.agents/plugins/marketplace.json   # Codex/agents marketplace
plugins/pcm/
  .claude-plugin/plugin.json       # plugin manifest
  .codex-plugin/plugin.json        # plugin manifest (Codex, adds `interface`)
  .mcp.json                        # bundled MCP servers
  assets/                          # logo + app icon
  skills/
    pcm-database/
      SKILL.md                     # required — the skill definition
      scripts/                     # optional helper scripts
      references/                  # optional docs, loaded on demand
    pcm-startlist/
      SKILL.md
```

Install the marketplace from a local clone to try changes, then exercise the skills with
realistic prompts and check they trigger on paraphrases — a description that misses is a bug.
Validation before opening a PR:

```bash
bash -n plugins/pcm/skills/pcm-database/scripts/open-cdb.sh   # syntax-check scripts
python3 -m json.tool <file>.json > /dev/null                  # validate manifests
npx prettier --check "**/*.{md,json}"                         # formatting
```

## Related projects

- [cdb-converter](https://github.com/PCMStack/converter) — lossless `.cdb` ⇄ SQLite conversion
- [pcm-mcp](https://github.com/PCMStack/mcp) — MCP server for querying and editing PCM databases
- [Agent Skills](https://agentskills.io/) — the portable skill format used here
