# Anneal — the 1-35-1 convergent improvement loop

**Name:** anneal. The 1-35-1 speculative process used to grind this repo from
draft to production-ready.

## What it is

1 orchestrator → 35 parallel stateless analysis candidates → one Jev `noul`
batch scores every candidate → argmax is applied after test verification.

Each candidate receives the repo's current state and returns two things:

- **Rationale** — what weakness it found and why the fix matters.
- **Unified git diff** — the whole change, as a patch, not prose. Jev grades
  the artifact, not the description of the artifact.

No grader subagent, no decider subagent. The score JSON is the decision.

## The loop

```
round N: 35 candidates → Jev batch → argmax → tests → merge → round N+1
```

Rounds repeat with the merged tree as the new base. The loop ends when
**Jev cannot give a clear winner**: top-two margin < 0.05. Below that gap,
scores are indistinguishable noise, not judgment — further rounds are
crowned randomness, not improvement. That is the convergence rule, and it is
the same 0.05 discrimination threshold this repo enforces in `v2-score`.

## The near-tie protocol

If the top two scores land within 0.05:

1. **Do not crown.** No winner ships on a noise margin.
2. **Tiebreak 1-2-1** — re-run the tied variants head-to-head with sharper
   contrasting variables.
3. **Or merge** — if both tiebreakers also no-result, take the best of both
   patches by hand and merge them as one commit.

## N judgment

- **35 for broad analysis rounds** — wide coverage of the weakness space in
  one pass. N is judged, not fixed: 35 because the task was "keep making
  changes," i.e. explore broadly, not crown one idea.
- **N=2 minimum for tiebreaks.**
- **Never N=1** — one candidate is asking once and pretending it's science.

## Kelly-split scoring context

The judge is split Kelly-style: **Jev provides the gut probability p**; a
separate **grade provides the multiplier b** (the risk discount — net odds).
Final rank = p × b. p comes only from Jev; b comes only from external
factors: discrimination margin, timeout history, test results, cost. See
README "Scoring: Kelly split" and CONSTRAINTS.md §5.

## What anneal actually did to this repo

- **Round 1 (1-35-1):** all 35 candidates independently found the same
  hole — the Jev judge's own response was never validated. A malformed or
  empty judge response would have sailed through scoring and crowned
  garbage. Jev scored the round **0.80 / 0.80 — a tie**, no crown.
- **Tiebreak (1-2-1):** the two leading fix variants scored **0.83 / 0.85**
  — still under the 0.05 gap. No-result again.
- **Merge (7+14):** both tied variants merged by hand into one commit:
  **7** = grader response validation (`bin/v2-score` rejects malformed /
  empty judge JSON, exit 4 on judge failure); **14** = fourteen new tests
  covering judge-response failure modes. That merge is HEAD:
  `156362d anneal merge: validate Jev judge response (7+14)`.

The loop converged exactly as designed: broad exploration, tied winners,
no crowning of noise, merge of the tied best. After this merge the repo
was declared production-ready.
