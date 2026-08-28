#!/usr/bin/env bash
# Discover every Pro Cycling Manager save (.cdb) on this machine and group them by game
# edition. Read-only: it stats files and never opens, copies or modifies a .cdb.
#
# Usage: find-saves.sh [--tsv] [--root DIR]...
#          --tsv       machine-readable output, one save per line, tab-separated
#          --root DIR  also scan DIR for "Pro Cycling Manager <year>" folders (repeatable)
#
# Requires bash, find, stat and date — nothing else. No Node, no sqlite3.

set -euo pipefail

TSV=0
EXTRA_ROOTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tsv) TSV=1; shift ;;
    --root)
      [[ $# -ge 2 ]] || { echo "error: --root needs a directory" >&2; exit 64; }
      [[ -d "$2" ]] || { echo "error: no such directory: $2" >&2; exit 66; }
      EXTRA_ROOTS+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: $0 [--tsv] [--root DIR]..." >&2; exit 64 ;;
  esac
done

command -v find >/dev/null || { echo "error: find not found on PATH" >&2; exit 69; }

# stat/date come in two incompatible flag dialects depending on the shell environment this
# runs in. Probe once instead of branching at every call site.
if stat -f '%m' / >/dev/null 2>&1; then
  file_mtime() { stat -f '%m' "$1"; }
  file_size() { stat -f '%z' "$1"; }
  fmt_date() { date -r "$1" '+%Y-%m-%d %H:%M'; }
else
  file_mtime() { stat -c '%Y' "$1"; }
  file_size() { stat -c '%s' "$1"; }
  fmt_date() { date -d "@$1" '+%Y-%m-%d %H:%M'; }
fi

human_size() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1073741824) printf "%.1f GB", b / 1073741824;
    else if (b >= 1048576) printf "%.0f MB", b / 1048576;
    else printf "%.0f KB", b / 1024;
  }'
}

ROOTS=()
add_root() { [[ -n "${1:-}" && -d "${1:-}" ]] && ROOTS+=("$1"); return 0; }

for r in ${EXTRA_ROOTS[@]+"${EXTRA_ROOTS[@]}"}; do add_root "$r"; done

# The per-user application-data folder PCM writes to. APPDATA is set in most shells; fall
# back to the same path under $HOME when it isn't.
add_root "${APPDATA:-}"
add_root "$HOME/AppData/Roaming"
# Older PCM editions kept their folder in Documents rather than AppData.
add_root "$HOME/Documents"

if [[ ${#ROOTS[@]} -eq 0 ]]; then
  echo "No candidate Pro Cycling Manager location exists on this machine." >&2
  echo "If the game is installed somewhere unusual, rerun with --root <dir>." >&2
  exit 0
fi

RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

# Roots overlap by design (APPDATA and ~/AppData/Roaming are often the same place), so the
# same save can be reached twice; sort -u on the absolute path collapses those later.
for root in "${ROOTS[@]}"; do
  while IFS= read -r edition_dir; do
    edition="$(basename "$edition_dir")"
    # "Pro Cycling Manager 2024" -> 2024. Anything without a year sorts last under 0000.
    year="$(printf '%s' "$edition" | grep -oE '[0-9]{4}' | tail -1 || true)"
    [[ -n "$year" ]] || year="0000"

    while IFS= read -r cdb; do
      rel="${cdb#"$edition_dir"/}"
      profile="$(dirname "$rel")"
      [[ "$profile" == "." ]] && profile="(edition root)"
      # The game writes careers into Cloud/<profile>/. A .cdb anywhere else under the
      # edition folder is the shipped game database or a community update, not something
      # the player played — worth reporting, but not as a save.
      case "$rel" in
        [Cc]loud/*) rank=0 ;;
        *) rank=1 ;;
      esac
      mtime="$(file_mtime "$cdb" 2>/dev/null)" || continue
      size="$(file_size "$cdb" 2>/dev/null)" || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$year" "$edition" "$profile" "$(basename "$cdb")" "$size" "$mtime" "$rank" "$cdb"
    done < <(find "$edition_dir" -type f -iname '*.cdb' 2>/dev/null)
  done < <(find "$root" -maxdepth 1 -type d -iname 'Pro Cycling Manager*' 2>/dev/null)
done | sort -u -t"$(printf '\t')" -k8,8 > "$RAW"

if [[ ! -s "$RAW" ]]; then
  echo "No Pro Cycling Manager saves found."
  echo
  echo "Scanned ${#ROOTS[@]} location(s) for a \"Pro Cycling Manager <year>\" folder:"
  printf '  %s\n' "${ROOTS[@]}"
  echo
  echo "The game may not be installed, or its saves may live elsewhere (a game library on"
  echo "another drive, a non-standard install). Rerun with --root <dir> pointing at the folder"
  echo "that contains \"Pro Cycling Manager <year>\"."
  exit 0
fi

# Newest edition first; within an edition, real saves before other databases, and the most
# recently played first — that is almost always the career the player means by "my save".
SORTED="$(sort -t"$(printf '\t')" -k1,1r -k7,7n -k6,6nr "$RAW")"

if [[ $TSV -eq 1 ]]; then
  printf 'year\tedition\tprofile\tfile\tbytes\tmtime_epoch\tkind\tpath\n'
  printf '%s\n' "$SORTED" | awk -F'\t' -v OFS='\t' \
    '{ $7 = ($7 == 0 ? "save" : "other"); print }'
  exit 0
fi

saves="$(printf '%s\n' "$SORTED" | awk -F'\t' '$7 == 0' | wc -l | tr -d ' ')"
others="$(printf '%s\n' "$SORTED" | awk -F'\t' '$7 == 1' | wc -l | tr -d ' ')"
editions="$(printf '%s\n' "$SORTED" | cut -f2 | sort -u | wc -l | tr -d ' ')"
echo "Found $saves player save(s) across $editions game edition(s)."
[[ "$others" -gt 0 ]] && echo "Plus $others other .cdb file(s) — game or community databases, not careers."

current=""
current_rank=""
while IFS=$'\t' read -r year edition profile file size mtime rank path; do
  if [[ "$edition" != "$current" ]]; then
    current="$edition"
    current_rank=""
    echo
    echo "$edition"
    printf '%s\n' "${edition//?/-}"
  fi
  if [[ "$rank" != "$current_rank" ]]; then
    current_rank="$rank"
    [[ "$rank" == "1" ]] && echo "  (not player saves)"
  fi
  printf '  %-28s %10s  %s  %s\n' \
    "$file" "$(human_size "$size")" "$(fmt_date "$mtime")" "$profile"
  printf '    %s\n' "$path"
done <<< "$SORTED"
