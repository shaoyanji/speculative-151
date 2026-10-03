#!/usr/bin/env bash
# test_score.sh — tests for bin/v2-score, esp. grader-response validation.
# A judge that returns a malformed batch or scores fewer than 2 candidates
# is a grader failure (exit 4), never a single-candidate "winner".
# Uses a stub jevq on PATH: canned response via FAKE_JEVQ_RESP, generated
# answers via MOCK_ANSWERS, garbage via MOCK_GARBAGE. No Jev credential needed.
# Merged from anneal candidates 7 (grader <2-scored) and 14 (per-slot
# numeric [0,1] validation + phantom-id drop).
# Run: bash tests/test_score.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   $1"; }
no()   { FAIL=$((FAIL+1)); echo "FAIL $1${2:+: $2}"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/jevq" <<'EOF'
#!/usr/bin/env bash
# stub jevq: FAKE_JEVQ_RESP file wins; else MOCK_ANSWERS JSON object;
# else MOCK_GARBAGE garbage; else scores every --batch id (0.8 for "1", 0.5 else).
if [[ -n "${FAKE_JEVQ_RESP:-}" ]]; then cat "$FAKE_JEVQ_RESP"; exit 0; fi
if [[ -n "${MOCK_GARBAGE:-}" ]]; then echo "this is not json"; exit 0; fi
if [[ -n "${MOCK_ANSWERS:-}" ]]; then
  jq -c -n --argjson ans "$MOCK_ANSWERS" '{answers: $ans}'; exit 0
fi
BATCH=""
for a in "$@"; do case "$a" in @*) BATCH="${a#@}";; esac; done
jq -c '{answers: ([.[] | .id]
  | map({key: ., value: {noul: (if . == "1" then 0.8 else 0.5 end)}})
  | from_entries)}' "$BATCH"
EOF
chmod +x "$T/bin/jevq"
export PATH="$T/bin:$PATH"

printf '{"1":"first answer","2":"second answer"}' > "$T/cands.json"
printf '[{"slot":1,"text":"aaa"},{"slot":2,"text":"bbb"},{"slot":3,"text":"ccc"}]' > "$T/cands3.json"
printf '{"answers":{"1":{"noul":0.8},"2":{"noul":0.4}}}' > "$T/resp_ok.json"
printf '{"answers":{}}' > "$T/resp_empty.json"
printf '{"answers":{"1":{"noul":0.8}}}' > "$T/resp_partial.json"
printf '{"answers":{"1":{"noul":0.8},"2":{"noul":"high"}}}' > "$T/resp_str.json"
printf '{"answers":{"1":{"noul":0.8},"2":{"noul":1.5}}}' > "$T/resp_range.json"
printf '{"nope":true}' > "$T/resp_noanswers.json"
printf '{"answers":{"1":{"noul":0.8},"2":{"noul":0.4},"9":{"noul":0.99}}}' > "$T/resp_phantom.json"

# 1. happy path: 2 scored -> SHIP exit 0, winner 1, margin 0.3
OUT="$(bin/v2-score --candidates "$T/cands.json" 2>/dev/null)"
CODE=$?
if [ "$CODE" = 0 ] \
  && echo "$OUT" | jq -e '.decision=="SHIP" and .winner==1' >/dev/null \
  && echo "$OUT" | jq -e '(.margin - 0.3 | fabs) < 0.000001' >/dev/null; then
  ok "happy path SHIP exit 0 winner 1 margin 0.3"
else
  no "happy path" "code=$CODE out=$OUT"
fi

# 2. judge scores only 1 candidate -> exit 4, never a lone winner
MOCK_ANSWERS='{"1":{"noul":0.95}}' bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 4 ] && ok "single-score grader failure exits 4" || no "single-score grader failure" "code=$CODE"

# 3. judge scores zero candidates -> exit 4 (was an opaque jq crash, exit 5)
MOCK_ANSWERS='{}' bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 4 ] && ok "zero-score grader failure exits 4" || no "zero-score grader failure" "code=$CODE"

# 4. judge returns non-JSON -> exit 4
MOCK_GARBAGE=1 bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 4 ] && ok "non-JSON grader failure exits 4" || no "non-JSON grader failure" "code=$CODE"

# 5. missing answers object -> exit 4
FAKE_JEVQ_RESP="$T/resp_noanswers.json" bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 4 ] && ok "no answers object -> exit 4" || no "no answers object" "code=$CODE"

# 6. one slot dropped by the judge (1 of 2 scored) -> exit 4 (was silently SHIP)
FAKE_JEVQ_RESP="$T/resp_partial.json" bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 4 ] && ok "partial answers -> exit 4" || no "partial answers" "code=$CODE"

# 7. non-numeric noul -> exit 4
FAKE_JEVQ_RESP="$T/resp_str.json" bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 4 ] && ok "string noul -> exit 4" || no "string noul" "code=$CODE"

# 8. noul outside [0,1] -> exit 4
FAKE_JEVQ_RESP="$T/resp_range.json" bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 4 ] && ok "out-of-range noul -> exit 4" || no "out-of-range noul" "code=$CODE"

# 9. malformed batch still emits a clear stderr message
ERR="$(FAKE_JEVQ_RESP="$T/resp_partial.json" bin/v2-score --candidates "$T/cands.json" 2>&1 >/dev/null)"
echo "$ERR" | grep "malformed jevq" >/dev/null \
  && ok "malformed batch stderr message" || no "malformed batch stderr message" "err=$ERR"

# 10. threshold gate still intact: top-two gap < 0.05 -> NO_RESULT exit 3
MOCK_ANSWERS='{"1":{"noul":0.80},"2":{"noul":0.78}}' bin/v2-score --candidates "$T/cands.json" >/dev/null 2>&1
CODE=$?
[ "$CODE" = 3 ] && ok "threshold NO_RESULT exit 3" || no "threshold NO_RESULT" "code=$CODE"

# 11. grades still applied on the valid path: grade flips the winner
MOCK_ANSWERS='{"1":{"noul":0.80},"2":{"noul":0.78}}' \
  bin/v2-score --candidates "$T/cands.json" --grades '{"1":0.5,"2":1.0}' 2>/dev/null \
  | jq -e '.decision=="SHIP" and .winner==2' >/dev/null \
  && ok "kelly grade flips winner" || no "kelly grade flips winner"

# 12. --scores-out still receives the raw p's on the valid path
FAKE_JEVQ_RESP="$T/resp_ok.json" bin/v2-score --candidates "$T/cands.json" \
  --scores-out "$T/raw.json" >/dev/null 2>&1
jq -e '.["1"]==0.8 and .["2"]==0.4' "$T/raw.json" >/dev/null \
  && ok "scores-out raw p's" || no "scores-out raw p's"

# 13. phantom ids dropped: judge invents slot 9 -> SHIP, raw scores carry only 1,2
OUT="$(FAKE_JEVQ_RESP="$T/resp_phantom.json" bin/v2-score --candidates "$T/cands.json" 2>/dev/null)"
CODE=$?
if [ "$CODE" = 0 ] \
  && echo "$OUT" | jq -e '.decision=="SHIP"' >/dev/null \
  && echo "$OUT" | jq -e '.raw_scores | has("9") | not' >/dev/null; then
  ok "phantom ids dropped"
else
  no "phantom ids dropped" "code=$CODE out=$OUT"
fi

# 14. flaky judge drops one of three: 2 of 3 scored >= 2 -> still SHIP (merge rule)
OUT="$(FAKE_JEVQ_RESP="$T/resp_ok.json" bin/v2-score --candidates "$T/cands3.json" 2>/dev/null)"
CODE=$?
if [ "$CODE" = 0 ] && echo "$OUT" | jq -e '.decision=="SHIP" and .winner==1' >/dev/null; then
  ok "2-of-3 scored still SHIP"
else
  no "2-of-3 scored still SHIP" "code=$CODE out=$OUT"
fi

echo
echo "pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
