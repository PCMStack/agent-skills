# PCM Agent Skills

A collection of skills for AI coding agents, focused on Pro Cycling Manager. Skills are packaged instructions and scripts that extend agent capabilities.

Skills follow the [Agent Skills](https://agentskills.io/) format, so they work with any agent that reads it.

PCM is a game built on files: a binary `.cdb` database holding your whole career, XML startlists, stage files, jersey textures, mods. All of it is editable — none of it is documented. These skills give an agent the knowledge to work on it safely.

## Available Skills

### pcm-db-editor

Opens, explores and edits Pro Cycling Manager save files and game databases (`.cdb`). Routes between the [pcm-mcp](https://github.com/mpicciolli/pcm-mcp) MCP server for saves living on your own machine, and a lossless `cdb → SQLite` conversion for files you can read directly — then writes changes back to a new file, never over your career.

**Use when:**

- "Show me the top 10 climbers in my save"
- "Bump Evenepoel's time trial rating to 82"
- "Which riders are out of contract at the end of the season?"
- Editing rider ratings, team rosters, contracts or races
- Exploring a `.cdb` database from any PCM year

**Topics covered:**

- Choosing between the MCP route and the SQLite round trip
- `cdb-converter` usage, including `--normalize` for real `PRIMARY KEY` / `FOREIGN KEY` constraints
- PCM naming conventions (`DYN_` vs `STA_`, `IDx` / `fkIDx`, `gene_sz_`)
- Discovery queries — column names drift between releases, so the real schema is always looked up first
- Ready-made queries for rosters, ratings, contracts, free agents and startlists
- Safe editing: backups, explicit output paths, no DDL, ID-keyed updates, verified round trips

## Planned Skills

The goal is to cover every part of the game a manager or modder actually touches:

| Skill                  | Scope                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| `pcm-startlist`        | Startlist XML for a race: team selection, rider IDs, filename conventions, where PCM expects the file. |
| `pcm-season-planner`   | Planning a season from the save: calendar, objectives, form peaks, which riders to send where.         |
| `pcm-transfer-market`  | Scouting and transfers: free agents, contract expiry, wages and market value, negotiation windows.     |
| `pcm-training`         | Training plans and form curves — what the system actually models, and how to peak for a target race.   |
| `pcm-database-modding` | Building a custom database: real-world rosters, new teams, imports, sanity checks before shipping.     |
| `pcm-stage-editor`     | Stage and route files: creating or tweaking a stage, profile data, terrain assets.                     |
| `pcm-jerseys-assets`   | Jersey, kit and logo files: formats, dimensions, naming, where each asset is loaded from.              |
| `pcm-mods-install`     | Installing and layering community mods and patches without breaking an existing career.                |
| `pcm-save-repair`      | Diagnosing a corrupted or non-loading save: what's recoverable, and how to salvage a career.           |

Open an issue if a skill you need is missing from this list, or if one of these should move up.

## Installation

```bash
npx skills add PCMStack/agent-skills
```

Or install a single skill by hand — a skill is just a folder. For Claude Code:

```bash
git clone https://github.com/PCMStack/agent-skills.git
ln -s "$PWD/agent-skills/skills/pcm-db-editor" ~/.claude/skills/pcm-db-editor
```

## Requirements

- [Node.js](https://nodejs.org) 22 or later — for `npx cdb-converter`
- `sqlite3` on your `PATH`

## Usage

Skills are automatically available once installed. The agent will use them when relevant tasks are detected.

**Examples:**

```
Open ~/Downloads/career.cdb and show me the top 10 climbers
```

```
Give every rider in my team +3 sprint
```

```
Which of my riders are out of contract at the end of the season?
```

> [!IMPORTANT]
> Your original `.cdb` is treated as read-only: it gets backed up first, and edits always go to a **new** file. Load the edited save in-game and verify it before deleting anything.

## Skill Structure

Each skill contains:

- `SKILL.md` — instructions for the agent
- `scripts/` — helper scripts for automation (optional)
- `references/` — supporting documentation, loaded on demand (optional)

## Resources

- [pcm-mcp](https://github.com/mpicciolli/pcm-mcp) — MCP server for Pro Cycling Manager saves
- [cdb-converter](https://www.npmjs.com/package/cdb-converter) — lossless `.cdb` ↔ SQLite converter
