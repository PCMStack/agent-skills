#!/usr/bin/env bash
# Open a PCM .cdb save for exploration: back it up, convert it to SQLite, and print a first
# inventory of its tables. Safe to re-run — refuses to clobber an existing .sqlite output.
#
# Usage: open_cdb.sh <save.cdb> [output.sqlite]
#
# Requires Node 22+ (for npx cdb-converter) and sqlite3.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <save.cdb> [output.sqlite]" >&2
  exit 64
fi

CDB="$1"
OUT="${2:-${CDB%.cdb}.sqlite}"

[[ -f "$CDB" ]] || { echo "error: no such file: $CDB" >&2; exit 66; }
[[ "$CDB" == *.cdb ]] || { echo "error: expected a .cdb file, got: $CDB" >&2; exit 64; }

if [[ -e "$OUT" ]]; then
  echo "error: $OUT already exists — pass a different output path or remove it first." >&2
  exit 73
fi

command -v sqlite3 >/dev/null || { echo "error: sqlite3 not found on PATH" >&2; exit 69; }

# The original save is the user's career. Keep an untouched copy before anything else.
BAK="$CDB.bak"
if [[ -e "$BAK" ]]; then
  echo "backup: $BAK already exists, keeping it"
else
  cp -- "$CDB" "$BAK"
  echo "backup: $BAK"
fi

# --normalize reconstructs PK/FK constraints from PCM naming conventions, which makes the
# schema self-describing (PRAGMA foreign_key_list works). It stays round-trip safe.
npx -y cdb-converter "$CDB" "$OUT" --normalize
echo "sqlite: $OUT"

echo
echo "Career tables (DYN_*) by row count:"
sqlite3 "$OUT" <<'SQL' |
SELECT name FROM sqlite_master
WHERE type = 'table' AND name LIKE 'DYN%'
ORDER BY name;
SQL
while IFS= read -r tbl; do
  [[ -n "$tbl" ]] || continue
  n=$(sqlite3 "$OUT" "SELECT COUNT(*) FROM \"$tbl\";")
  printf '%10s  %s\n' "$n" "$tbl"
done | sort -rn

echo
echo "Next: sqlite3 -header -column $OUT \"PRAGMA table_info(DYN_cyclist);\""
echo "Write edits back with: npx -y cdb-converter $OUT ${CDB%.cdb}_edited.cdb"
