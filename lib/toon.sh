#!/usr/bin/env bash
# toon.sh — TOON parse helpers. TOON = Token-Oriented Object Notation,
# CSV disguised as modern YAML: headers + rows, compact and jq-friendly.
# Source from scripts: source "$(dirname "$0")/../lib/toon.sh"

set -euo pipefail

# toon_rows FILE TABLE -> print data rows of TABLE (strips indent, skips header/comment lines).
# A table header looks like:  name[N]{f1,f2}:
toon_rows() {
  local file="$1" table="$2"
  awk -v t="$table" '
    $0 ~ "^"t"\\[" { in_table=1; next }
    in_table && /^[^ ]/ { in_table=0 }
    in_table && /^[[:space:]]/ { sub(/^[[:space:]]+/, ""); print }
    in_table && /^$/ { next }
  ' "$file"
}

# toon_json_rows FILE TABLE -> for tables whose rows are '{...}' JSON docs,
# print each row's JSON (indent stripped) for piping to jq.
toon_json_rows() {
  toon_rows "$1" "$2" | grep -o '{.*}' || true
}

# toon_header FILE TABLE -> print the header line of TABLE (e.g. candidates[5]{slot,variable,prompt}:)
toon_header() {
  local file="$1" table="$2"
  grep -E "^${table}\\[" "$file" | head -1 || true
}

# toon_table_names FILE -> list all table names declared in FILE.
toon_table_names() {
  grep -oE '^[a-z_0-9]+\[' "$file" | tr -d '[' | sort -u || true
}
