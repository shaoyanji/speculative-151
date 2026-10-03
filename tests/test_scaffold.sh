#!/usr/bin/env bash
# test_scaffold.sh — tests for bin/v2-scaffold guardrails.
# Run: bash tests/test_scaffold.sh
# Note: uses `grep PAT >/dev/null` (not `grep -q`) because `grep -q`
# exits early -> SIGPIPE -> pipefail turns it into exit 141.
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   $1"; }
no()   { FAIL=$((FAIL+1)); echo "FAIL $1${2:+: $2}"; }
G()    { grep "$@" >/dev/null; }  # full-consumption grep for pipefail safety

# N=1 rejected (nothing to judge)
if bin/v2-scaffold --prompt "x" --slots 1 >/dev/null 2>&1; then no "slots=1 accepted"; else ok "slots=1 rejected"; fi
# N=0 rejected
if bin/v2-scaffold --prompt "x" --slots 0 >/dev/null 2>&1; then no "slots=0 accepted"; else ok "slots=0 rejected"; fi
# N=26 rejected (max 25)
if bin/v2-scaffold --prompt "x" --slots 26 >/dev/null 2>&1; then no "slots=26 accepted"; else ok "slots=26 rejected"; fi
# N=25 ok
if bin/v2-scaffold --prompt "x" --slots 25 --json 2>/dev/null | jq -e '.slots==25' >/dev/null; then ok "slots=25 ok"; else no "slots=25"; fi
# N=2 ok (minimum)
if bin/v2-scaffold --prompt "x" --slots 2 --json 2>/dev/null | jq -e '.slots==2 and (.rows|length)==2' >/dev/null; then ok "slots=2 ok"; else no "slots=2"; fi
# empty prompt rejected
if bin/v2-scaffold --prompt "" >/dev/null 2>&1; then no "empty prompt accepted"; else ok "empty prompt rejected"; fi
# missing prompt rejected
if bin/v2-scaffold >/dev/null 2>&1; then no "missing prompt accepted"; else ok "missing prompt rejected"; fi
# bad variable rejected
if bin/v2-scaffold --prompt "x" --variables "ok,bad var" >/dev/null 2>&1; then no "bad variable accepted"; else ok "bad variable rejected"; fi
# default: 5 rows, shape 1-5-1, valid TOON + JSON
OUT="$(bin/v2-scaffold --prompt "Why is the sky blue?")"
echo "$OUT" | G '^dispatch\[5\]{slot,variable,expanded_prompt}:$' && ok "toon header" || no "toon header"
[ "$(echo "$OUT" | grep -c '^  [0-9],')" = "5" ] && ok "5 rows" || no "5 rows"
echo "$OUT" | grep '^# json: ' | sed 's/^# json: //' | jq -e '.shape=="1-5-1" and (.rows|length)==5' >/dev/null && ok "embedded json" || no "embedded json"
# header comment adapts to slots (wart fix)
bin/v2-scaffold --prompt "x" --slots 3 | G '# toon: v2 1-3-1 dispatch spec' && ok "header adapts" || no "header adapts"
# --json pure mode
bin/v2-scaffold --prompt "x" --json | jq -e '.protocol=="v2"' >/dev/null && ok "--json mode" || no "--json mode"
# template file
printf 'SLOT {SLOT} | {VAR_UPPER} | {PROMPT}\n' > /tmp/tmpl-test.txt
bin/v2-scaffold --prompt "hi" --slots 2 --template /tmp/tmpl-test.txt | G 'SLOT 1 | BRIEF | hi' && ok "template" || no "template"
# prompt is hashed in metadata (raw prompt only appears inside expanded_prompt rows, by design)
bin/v2-scaffold --prompt "supersecret" --json | jq -e '.prompt_sha | test("^[0-9a-f]{64}$")' >/dev/null && ok "prompt hashed" || no "prompt hashed"
bin/v2-scaffold --prompt "supersecret" --json | jq -e 'has("prompt") | not' >/dev/null && ok "no raw prompt field" || no "no raw prompt field"
# variables cycle
bin/v2-scaffold --prompt "x" --variables "a,b" --slots 4 --json | jq -e '[.rows[].variable]==["a","b","a","b"]' >/dev/null && ok "variable cycling" || no "variable cycling"

echo
echo "pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
