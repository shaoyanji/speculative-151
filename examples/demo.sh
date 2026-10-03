#!/usr/bin/env bash
# demo.sh — end-to-end v2 1-5-1 run with canned candidates.
# Shows: scaffold -> candidates (simulated) -> jev score -> argmax -> ledger.
# Requires: jq, jevq on PATH (real Jev call is made).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== 1. scaffold ==="
bin/v2-scaffold --prompt "Why is the sky blue?" --slots 5

echo
echo "=== 2. candidates (simulated — in production these come from 5 parallel subagents) ==="
cat > /tmp/demo-cands.json <<'EOF'
{"1":"Sunlight scatters off air molecules; blue scatters most.","2":"Rayleigh scattering: intensity scales as 1/λ⁴, so blue dominates.","3":"The sky ran out of other colors and settled.","4":"Blue scatters most.","5":"Air molecules scatter blue hardest. That's the trick."}
EOF
cat /tmp/demo-cands.json | jq .

echo
echo "=== 3. score + argmax ==="
bin/v2-score --candidates /tmp/demo-cands.json --ledger /tmp/demo-ledger.jsonl || {
  code=$?
  if (( code == 3 )); then echo "(NO_RESULT: top-two gap below threshold — re-run or merge, do not ship)"; fi
  exit "$code"
}

echo
echo "=== 4. ledger ==="
cat /tmp/demo-ledger.jsonl | jq .
