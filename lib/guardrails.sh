#!/usr/bin/env bash
# guardrails.sh — shared validation for the speculative-151 toolchain.
# Source from bin scripts:  source "$(dirname "$0")/../lib/guardrails.sh"
# Requires: bash >= 4.

set -euo pipefail

# --- invariants -----------------------------------------------------------
SPEC_MIN_SLOTS=2
SPEC_MAX_SLOTS=25
SPEC_WARN_SLOTS=10
SPEC_PROMPT_MAX_CHARS=8000

# guard_slots N -> validated N on stdout; exits 2 on violation.
guard_slots() {
  local n="${1:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "error: --slots must be a positive integer, got '$n'" >&2; return 2; }
  if (( n < SPEC_MIN_SLOTS )); then
    echo "error: --slots must be >= ${SPEC_MIN_SLOTS} (N=1 has nothing to judge; argmax would be a no-op)" >&2
    return 2
  fi
  if (( n > SPEC_MAX_SLOTS )); then
    echo "error: --slots must be <= ${SPEC_MAX_SLOTS} (cost control)" >&2
    return 2
  fi
  if (( n > SPEC_WARN_SLOTS )); then
    echo "warn: --slots=$n exceeds ${SPEC_WARN_SLOTS}; 1-N-1 cost scales ~linearly with N" >&2
  fi
  printf '%s' "$n"
}

# guard_prompt TEXT -> validated text on stdout; exits 2 on violation.
guard_prompt() {
  local text="${1:-}"
  [[ -n "$text" ]] || { echo "error: --prompt is required and must not be empty" >&2; return 2; }
  if (( ${#text} > SPEC_PROMPT_MAX_CHARS )); then
    echo "error: --prompt exceeds ${SPEC_PROMPT_MAX_CHARS} chars (bound jevq input cost)" >&2
    return 2
  fi
  printf '%s' "$text"
}

# guard_variables CSV -> validated CSV on stdout; exits 2 on violation.
guard_variables() {
  local csv="${1:-}"
  [[ -n "${csv//,/}" ]] || { echo "error: --variables must name at least one variable" >&2; return 2; }
  local v
  IFS=',' read -ra _vs <<< "$csv"
  for v in "${_vs[@]}"; do
    [[ "$v" =~ ^[A-Za-z0-9_-]+$ ]] || {
      echo "error: invalid variable '$v' (use [A-Za-z0-9_-])" >&2; return 2; }
  done
  printf '%s' "$csv"
}

# guard_threshold T -> validated threshold on stdout; exits 2 on violation.
guard_threshold() {
  local t="${1:-0.05}"
  [[ "$t" =~ ^0?\.[0-9]+$|^1(\.0+)?$ ]] || {
    echo "error: --threshold must be in (0,1], got '$t'" >&2; return 2; }
  printf '%s' "$t"
}

# prompt_sha TEXT -> sha256 hex of prompt (for ledger; never logs the prompt itself).
prompt_sha() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

# guard_grade G -> validated grade on stdout; must be a number in (0,1].
# The grade is the Kelly multiplier b: a risk discount from factors OUTSIDE
# Jev (timeout history, test results, cost, discrimination margin). It is
# never sourced from Jev itself — p and b stay separate.
guard_grade() {
  local g="${1:-}"
  [[ "$g" =~ ^[0-9]*\.?[0-9]+$ ]] || {
    echo "error: grade must be a number in (0,1], got '$g'" >&2; return 2; }
  awk -v g="$g" 'BEGIN{exit !(g > 0 && g <= 1)}' || {
    echo "error: grade must be in (0,1], got '$g'" >&2; return 2; }
  printf '%s' "$g"
}
