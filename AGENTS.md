# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

`agent-skills` (published as the **PCMStack** marketplace) is a content repository of agent
skills and plugins for [Pro Cycling Manager](https://www.cyanide-studio.com/) — an unofficial
community project, not affiliated with Cyanide Studio or Nacon.

There is **no application code**: no `package.json`, no build step, no test suite, no CI. The
deliverables are Markdown, JSON manifests, and a shell script. Everything an agent changes
here is read by _another_ agent at runtime, so prose quality and accuracy are the product.

Key formats and technologies:

- [Agent Skills](https://agentskills.io/) — the `SKILL.md` format, portable across agents.
- Claude Code plugin + marketplace manifests (`.claude-plugin/`).
- Codex plugin manifests (`.codex-plugin/`) and the `.agents/plugins/` marketplace.
- MCP servers declared per-plugin in `.mcp.json`.
- Bash scripts; SQLite (`sqlite3`) and Node 22+ (`npx`) at skill runtime, not at authoring time.

### Repository Layout

```
.claude-plugin/marketplace.json   # Claude Code marketplace definition
.agents/plugins/marketplace.json  # Codex/agents marketplace definition
plugins/
  pcm/
    .claude-plugin/plugin.json    # Claude Code plugin manifest
    .codex-plugin/plugin.json     # Codex plugin manifest (adds `interface` block)
    .mcp.json                     # MCP servers bundled with the plugin (pcm-mcp)
    assets/                       # logo.svg + app-icon.png, referenced by the Codex manifest
    skills/
      pcm-database/               # kebab-case
        SKILL.md                  # Required: skill definition
        scripts/open-cdb.sh       # Optional: {script-name}.sh / .mjs
        references/               # Optional: docs loaded on demand
      pcm-startlist/
        SKILL.md
AGENTS.md / CLAUDE.md             # CLAUDE.md is a one-line `@AGENTS.md` include
README.md                         # human-facing; keep it short, guidance lives here
```

Skills live **inside a plugin** (`plugins/{plugin}/skills/{skill}/`), not at the repo root.
The only plugin is `pcm`, containing `pcm-database` and `pcm-startlist`.

## Setup Commands

No install step. Clone and edit.

Optional tools used when validating changes (invoked ad hoc via `npx`, not dependencies):

```bash
npx prettier --check "**/*.{md,json}"   # formatting
```

To exercise a skill end-to-end you need the runtime prerequisites the skills themselves
require: **Node 22+** (for `npx cdb-converter`) and **sqlite3** on `PATH`. A real `.cdb`
file is needed for anything beyond a dry read — never commit one.

## Development Workflow

Install the marketplace locally in Claude Code to test plugin changes:

```
/plugin marketplace add /Users/<you>/Dev/agent-skills
/plugin install pcm@pcmstack
```

Then exercise the skill with realistic prompts (e.g. "who's the best climber in my team?",
"build the startlist for the Tour de France") and check that it triggers _and_ that the
instructions hold up. The `defaultPrompt` array in
[plugins/pcm/.codex-plugin/plugin.json](plugins/pcm/.codex-plugin/plugin.json) is a good
source of test prompts.

Prefer the `/skill-creator:skill-creator` skill (if available in your agent environment,
otherwise skip it) to create or improve a skill. It walks through capturing intent, drafting
`SKILL.md`, running test prompts, and optimizing the description for reliable triggering.
Then apply the repository conventions below to the result.

## Testing Instructions

There is no automated test suite. "Testing" here means validation plus behavioural checks:

```bash
bash -n plugins/pcm/skills/pcm-database/scripts/open-cdb.sh   # syntax-check scripts
python3 -m json.tool <file>.json > /dev/null                  # validate each JSON manifest
npx prettier --check "**/*.{md,json}"                         # formatting
```

Behavioural checks that matter more than the above:

- **Triggering** — install the plugin and confirm the skill fires on paraphrases, not just the
  exact words in its `description`, and in French as well as English (users write both).
  Descriptions are the trigger surface; treat a miss as a bug in the description.
- **Cross-manifest consistency** — a skill or plugin added or renamed under `plugins/` must
  stay resolvable from both `plugin.json` files (`"skills": "./skills/"`) and both marketplace
  files. Renames are the main source of breakage here; grep the old name repo-wide.
- **Script safety** — every script must refuse to clobber user data. `open-cdb.sh` backs up
  the `.cdb` first and exits rather than overwriting an existing output; keep that property.
- **Factual accuracy** — schema notes under `references/` describe a real game database. If you
  can't verify a column or constraint against an actual `.cdb`, don't assert it.

## Code Style

### Naming Conventions

- **Plugin directory**: `kebab-case` (e.g. `pcm`), matching `name` in both plugin manifests.
- **Skill directory**: `kebab-case` (e.g. `pcm-database`), matching `name` in its frontmatter.
- **SKILL.md**: always uppercase, always this exact filename.
- **Scripts**: `kebab-case.sh` or `kebab-case.mjs` (e.g. `open-cdb.sh`).
- **References**: `kebab-case.md` (e.g. `database-schema.md`).

### SKILL.md

- YAML frontmatter with `name` (matching the directory) and `description`.
- The `description` is what an agent matches a user request against: state what the skill does
  **and when to use it**, including phrasings and languages users actually type. Existing
  descriptions list trigger phrases explicitly — follow that pattern.
- Body is prose in the second person addressed to the agent, explaining _why_ a rule exists,
  not just the rule. Lead with the decision the agent has to make.
- Keep `SKILL.md` focused; push long schema dumps and constraint lists into `references/` and
  point at them from the body so they load on demand.
- Wrap Markdown at ~95 characters, matching the existing files.

### Shell scripts

- `#!/usr/bin/env bash` + `set -euo pipefail`.
- Header comment: what it does, `Usage:` line, and required runtime.
- Validate argument count and file existence up front; exit with meaningful codes
  (`64` usage, `66` missing input, `69` missing dependency, `73` refusing to overwrite).
- Comment the non-obvious decisions — why a backup keeps the `.cdb` extension, why
  `--normalize` is passed — rather than restating the command.
- `chmod +x` new scripts.

### JSON manifests

- Two-space indent; keep `$schema` where present.
- Descriptions in manifests are user-facing marketing copy; keep the "Unofficial, not
  affiliated with Cyanide Studio or Nacon" disclaimer wherever it already appears.
- Bump the plugin `version` in **both** `.claude-plugin/plugin.json` and
  `.codex-plugin/plugin.json` together — they must not drift (both are `0.1.0` today).

## Build and Deployment

There is no build. Distribution is the git repository itself: users add
`https://github.com/PCMStack/agent-skills` as a marketplace and the manifests at the root are
read directly. Merging to `main` is the release.

Consequences worth remembering:

- Every path in a manifest is resolved relative to that manifest's plugin directory or the
  repo root — a broken relative path ships silently.
- Adding a new plugin means a new `plugins/{name}/` directory **plus** entries in both
  `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`.
- Plugin assets are resolved relative to the plugin directory, which is why `assets/` lives
  under `plugins/pcm/` rather than at the repo root.

## Pull Request Guidelines

- Commit and PR titles follow Conventional Commits: `feat:`, `docs:`, `fix:` — e.g.
  `feat: add pcm-startlist skill`.
- One skill or one coherent change per PR.
- Before opening: JSON manifests parse, scripts pass `bash -n`, and the skill has been
  exercised against at least a few realistic prompts. Say in the PR description what you
  tested it with.
- Branch off `main`; `main` is the release branch.

## Security and Data Handling

- **Never commit a `.cdb` file, a save, or anything from a user's game directory.** They are
  large, personal, and copyrighted game data.
- Skills operate on files that may be irreplaceable (a career save can be hundreds of hours).
  The invariant every skill and script must preserve: **treat the original `.cdb` as
  read-only** — back it up, write edits to a new file, never overwrite in place.
- No secrets or credentials belong in this repository. The bundled MCP server (`pcm-mcp`, run
  via `npx -y pcm-mcp`) runs locally on the user's machine and needs none.
- `.claude/settings.local.json` is local, machine-specific permission state — don't extend it
  as a way to encode project conventions, and don't rely on paths inside it.

## Additional Notes

- `CLAUDE.md` is deliberately a single `@AGENTS.md` include. Keep guidance in this file only.
- `README.md` still lists "Coming soon" under Available Skills; it lags the actual contents.
- Related projects, useful when a skill's behaviour depends on them:
  [cdb-converter](https://github.com/PCMStack/converter) (lossless `.cdb` ⇄ SQLite) and
  [pcm-mcp](https://github.com/PCMStack/mcp) (MCP server for querying/editing PCM databases).
