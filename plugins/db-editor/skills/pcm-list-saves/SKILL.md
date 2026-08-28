---
name: pcm-list-saves
description: >-
  Find every Pro Cycling Manager save (.cdb) on the player's own machine and list them
  grouped by game edition (PCM 2023, 2024, 2025…), newest first, with profile, size, last
  played date and absolute path. Uses the pcm_list_saves MCP tool when it is available, and
  falls back to a bundled filesystem scan otherwise. Use this skill whenever someone asks
  where their PCM saves are, wants to see or choose among their careers, mentions having
  several saves or several editions of the game, or asks a question about "my save" / "my
  career" / "my team" without giving a file path — locate the save first, then hand the path
  to pcm-database. Triggers on "list my saves", "where are my PCM saves", "find my career",
  "show my careers", "which save should I open", "I have several saves".
---

# Finding Pro Cycling Manager saves on this machine

Pro Cycling Manager writes each career to a `.cdb` file somewhere under a
`Pro Cycling Manager <year>` folder on the player's computer. Your job is to find all of
them, across every edition installed, and present them clearly enough that the user can say
"that one" — because almost every other PCM task starts with an absolute path to a `.cdb`,
and guessing that path wastes everyone's time.

Two words from `pcm-database` are used precisely here. A **save** is a `.cdb` the game wrote
as the player played, living under an edition's `Cloud/<profile>/` folder. Any other `.cdb`
under the edition folder is the shipped game database or a community update — real, worth
mentioning, but not a career. Keep them apart in what you report; a user asking for "my
saves" who gets handed the stock database will load it and find their career gone.

## Try the MCP tool first, then the script

Look at your tool list. If `pcm_list_saves` is there — the `pcm-mcp` server is bundled with
this plugin, so it usually is — call it first. It is the fastest path to an answer and it
returns the same facts this skill reports: profile, file, size, last played, absolute path.

Fall back to the bundled script whenever the MCP tool isn't available, returns nothing, or
errors:

```bash
scripts/find-saves.sh
```

That's the whole discovery step. Resist the urge to `find / -name '*.cdb'` or to reason your
way to a path from what you remember about where games store things — the script encodes the
locations PCM actually uses, including older editions that stored saves elsewhere, and a
broad filesystem walk is slow and noisy.

The script is read-only — it stats files and never opens, copies or modifies a `.cdb`. It is
safe to run without asking, and safe to re-run.

Two flags matter:

- `--root DIR` — also scan `DIR` for `Pro Cycling Manager <year>` folders. This is the answer
  whenever the default locations come up empty: a game library on a second drive, a
  non-standard install, saves copied to an external disk. Repeatable.
- `--tsv` — one save per line, tab-separated (`year`, `edition`, `profile`, `file`, `bytes`,
  `mtime_epoch`, `kind`, `path`), with `kind` being `save` or `other`. Use this when you need
  to filter or pick programmatically rather than show a list.

## When nothing is found

The script says so plainly and prints every location it scanned. Don't paper over that with a
plausible-looking path — a wrong path sends the user hunting for a file that was never there.
Show them what was searched, then ask the one useful question: where is the game installed,
or can they drag a `.cdb` into the conversation? Rerun with `--root` once they answer.

Common real causes, worth offering: the game lives in a library on another drive; it was
installed somewhere the default locations don't cover; PCM simply isn't installed on this
machine (they may have been playing on another one).

## Reporting back

Group by edition, newest edition first, and within an edition put the most recently played
save first — that ordering is doing real work, because the top entry is almost always the
career the user means by "my save". The script already sorts this way, so lean on its output
rather than re-deriving an order.

For each save give the file name, the profile it belongs to, its size, when it was last
written, and the absolute path. The date is the useful discriminator when someone has five
saves with names like `save1.cdb` — it is the last time that career was played. The path
matters because it's what every other tool needs next.

Keep it to a compact table or list. If a single edition has a dozen saves, show them all —
the user asked for all of them — but don't pad each one with commentary.

Be honest about what the file names tell you, which is very little. PCM save names are
whatever the player typed, so a file called `Tour 2024.cdb` may hold any team in any season.
If the user needs to know which career is which — team, year, rider — that is a question
about the _contents_, and it means opening the database.

## Handing off

Finding the save is usually step one of something bigger. Once the user picks one, carry the
absolute path forward and switch to `pcm-database` to open it, or `pcm-startlist` if they
want a race startlist. Don't re-run discovery later in the conversation; keep the path in
context, since those tools are stateless and need it on every call.

## MCP tool vs. script, in one line

`pcm_list_saves` is the default when it's in your tool list; `scripts/find-saves.sh` is the
fallback. An empty result from the MCP tool is not proof there are no saves — run the script
before telling the user they have none.
