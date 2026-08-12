# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this repository is

A collection of skills for AI coding agents working with the Pro Cycling Manager game. Skills are packaged instructions and scripts that extend agent capabilities.

## Creating a New Skill

Skills follow the [Agent Skills](https://agentskills.io/) format, so they work with any agent that reads it.

Prefer the `/skill-creator:skill-creator` skill (if available in your agent environment, otherwise skip this step) to create a new skill (or to edit and
improve an existing one). It walks through capturing intent, drafting `SKILL.md`, running
test prompts, and optimizing the description for reliable triggering. Then apply the
repository conventions below to the result.

### Directory Structure

```
skills/
  {skill-name}/           # kebab-case directory name
    SKILL.md              # Required: skill definition
    scripts/              # Optional: executable scripts
      {script-name}.sh    # Bash scripts
      {script-name}.mjs   # Node scripts
    references/           # Optional: supporting docs loaded on demand
    lib/                  # Optional: shared code for scripts
```

### Naming Conventions

- **Skill directory**: `kebab-case` (e.g., `pcm-db-editor`)
- **SKILL.md**: Always uppercase, always this exact filename
- **Scripts**: `kebab-case.sh` or `kebab-case.mjs` (e.g., `open-cdb.sh`)
