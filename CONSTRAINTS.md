# CONSTRAINTS.md — operational rules for running 1-N-1

These are load-bearing. Violating them silently is how the weaknesses in
`README.md` turn from documented risks into live incidents.

## 1. Minimum N: 2
Never run N=1. A single candidate makes Jev scoring vacuous — `argmax`
over one score is a no-op and the protocol degrades to a pass-through
with extra steps. `v2-scaffold --slots 1` is rejected by the runner; treat
any 1-1-1 dispatch as a bug.

## 2. Discrimination threshold: 0.05
If the top-two final scores land within 0.05, declare **no-result**. Do not
crown noise. On no-result, either:
- re-run with sharper contrasting variables, or
- merge the best of the top two instead of picking one.
(Batch p's run hot — see 9 — so 0.05 is a floor, not a precision claim.)

## 3. The grader stage is independent — no cascading timeouts
The scoring stage (`bin/v2-score`) has its OWN timeout (default 120s):
`timeout -k 10` sends TERM at the deadline and hard-KILLs 10s later, so
the grader can never hang. A grader timeout or failure exits **4**
immediately.

Candidate-generation timeouts NEVER cascade into scoring. The fan-out
stage and the judge stage are separate, independently bounded stages:
- Per-candidate timeouts belong to the orchestrator/fan-out stage.
- Scoring proceeds with however many candidates finished — empty or
  missing candidates are dropped, not waited on.
- Fewer than 2 finishers is a loud failure (exit 2), never a
  single-candidate "winner" (see 1).

Long cascading timeouts paralyzing the grader was a real failure mode:
one hung candidate used to stall the whole pipeline. That is fixed by
construction now — the judge never waits on the fan-out.

The same loud-failure rule mirrors at the grader stage: if Jev scores
fewer than 2 candidates, or its response is unusable, that is a grader
failure (exit 4) — never a single-candidate "winner".

## 4. Always capture the raw first Jev score
The unmodified first-preference `noul` probabilities — the gut p per
candidate — are emitted BEFORE any grade multiplication, discounting, or
`NO_RESULT` logic:
- printed to stderr as `raw_scores: {...}` immediately after the Jev call,
- written to `--scores-out FILE` if given,
- included in every ledger line alongside the final decision.

Ledger lines therefore always carry BOTH the raw scores and the final
decision. The first preference is never lost to downstream adjustments —
if the grades or the threshold change the outcome, the raw p's are still
there to audit against.

## 5. Kelly-split scoring: p from Jev, b from the grade
Final rank score per candidate = **Jev p × grade**, like the Kelly
criterion: Jev provides the gut probability, a separate grade provides
the multiplier (the b risk-discount, net odds).

- **p comes ONLY from Jev.** The raw `noul` probability is the model's
  unadjusted read of "is this the best response?" Nothing else touches it.
- **b comes ONLY from the grade.** Each grade is a number in (0,1],
  derived from additional factors OUTSIDE Jev. It is never sourced from
  Jev itself — p and b are never mixed at the source.
- Factors that may feed the grade: discrimination-margin history for this
  prompt type, candidate timeout history, test/verification results
  (e.g. `git apply --check`, test suites), cost/latency budgets.
- Without `--grades`, every grade defaults to 1.0: pure Jev ranking, the
  legacy behavior.

Pass grades as `--grades '{"1":0.9,"2":0.7}'` or `--grades @grades.json`.
Missing slots default to 1.0. Out-of-range grades are rejected.

## 6. Git patches for parallel edits
Parallel code edits ship as unified diffs, never as prose describing
changes. Jev grades the diff. Reject candidates with broken hunks before
they touch the tree (`git apply --check`). The winning diff is the audit
trail. See `docs/PARALLEL_EDITS.md` — hunk-check and test results are
natural grade factors (see 5).

## 7. Log the ledger
Every run appends one line: prompt hash (never the prompt), N, raw
scores, grades, final scores, winner id, margin, decision, timestamps.
Without the ledger, "trust the process" is unfalsifiable (README
weakness 14 → now weakness 10's closing note).

## 8. Price the fan-out
1-N-1 is for open-ended, subjective, or tone-sensitive prompts where
"best" is ambiguous. For factual lookups, tool calls, and trivial
confirmations, a single subagent relay is cheaper and no worse. N itself
is a routing decision — price it, don't blanket it.

## 9. Discount batch probabilities
Treat every batch-mode noul p as an **upper bound**. Discount before
Kelly or any threshold math. The ranking is the signal; the absolute
numbers flatter the winner. (This is separate from the grade multiplier
in 5 — the hot-p discount is about Jev's calibration, the grade is
about external risk factors.)

## 10. Blind candidates by default
Do not publish a speculative pre-draft before candidates run, and do not
let candidates peek at neighbors' roles, unless you have explicitly
decided that coordinated coverage beats independent diversity for this
message — and logged that decision. Default: blind.
