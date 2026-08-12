# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A collection of [Agent Skills](https://agentskills.io/) for Pro Cycling Manager, published as `PCMStack/agent-skills` and installed via `npx skills add PCMStack/agent-skills`. There is no build, no test suite, and no lint config — the deliverable is prose plus a few helper scripts. "Working on this codebase" almost always means writing or revising skill instructions.

The audience for every file under `skills/` is an _agent_, not a human. Content is judged on whether it changes what an agent does: what route it picks, what it verifies, what it refuses to do.

## Layout

```
skills/<skill-name>/
  SKILL.md          # always loaded — frontmatter + instructions
  references/*.md   # loaded on demand, only when SKILL.md says to
  scripts/*.sh      # optional helpers, invoked by the agent
```

`README.md` at the root doubles as the public index: it lists shipped skills, and a "Planned Skills" table of the ~9 remaining domains (startlists, season planning, transfers, training, modding, stages, assets, mods, save repair). **When a new skill ships, move it out of that table into "Available Skills" in the same commit** — the README is the only place the roadmap lives.

## Writing a SKILL.md

Follow `skills/pcm-db-editor/SKILL.md` as the reference implementation; it encodes the house style.

- **Frontmatter is `name` + `description` only.** The description is the trigger — it must be long and over-inclusive, listing the vocabulary a user would actually use _and_ explicitly covering the cases where they never say the technical term ("even if they never say the words 'cdb' or 'database', and even if they only want to read something"). Under-triggering is the failure mode that matters.
- **Explain the reasoning, not just the rule.** Every constraint states _why_, so the agent can generalize when reality doesn't match the doc — e.g. no DDL "because the CDB data types and column indices are encoded in each column's declared type string".
- **Split by load cost.** SKILL.md carries decision-making (which route, what's forbidden, how to report). `references/` carries lookup material (naming tables, worked queries). SKILL.md must name the reference file _and the moment to read it_ ("as soon as you're writing anything beyond a single-table SELECT").
- **Route tables over prose** when there's a fork in the road, and state the discriminating fact — pcm-db-editor routes purely on _where the file physically lives_, because that determines what can touch it.
- Prefer imperatives with a stated cost ("`cp save.cdb save.cdb.bak` costs nothing") over generic caution.

## Non-negotiable domain invariants

These hold across every current and planned skill, because a PCM career represents hundreds of hours:

- The user's original file is **read-only**. Back it up before touching anything; write results to a _new_ file.
- **Watch default output paths.** `npx cdb-converter save.sqlite` writes to `save.cdb` — plausibly the user's original. Always pass an explicit output path.
- **Never answer from memory about PCM's schema.** Column names drift between game years (2014→2026 share the container format, not the columns). Every recipe in `references/` starts from a discovery query for this reason; keep it that way when adding recipes.
- Tell the user to load the edited file in-game and verify before deleting the backup.

## Scripts

Bash, `set -euo pipefail`, distinct exit codes (64 usage / 66 missing input / 69 missing dependency / 73 output exists), and **refuse to clobber** rather than prompt. Each script ends by printing the next commands the agent should run, so the script hands control back rather than being a black box. External dependencies are Node 22+ (`npx cdb-converter`) and `sqlite3` on PATH — check for them and exit cleanly if absent.

Test a script change by running it against a real `.cdb`; there is no harness.
