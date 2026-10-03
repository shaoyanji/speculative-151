# Parallel edits with git patches

When the 1-N-1 shape is used for **code changes** (not prose), candidates
must output their work as **git unified diffs**, not as descriptions of
changes. This lets Jev grade whole repo changes instead of prose about
changes.

## Candidate contract

Each candidate subagent receives its expanded prompt (from `v2-scaffold`)
plus this instruction appended:

> Implement the change described above. Output ONLY a unified git diff
> (`git diff` format) against the repo root. No explanation, no prose
> outside the diff. If you cannot produce a working change, output an
> empty diff.

## Scoring diffs

Collect the diffs into a candidates file:

```json
{"1": "diff --git a/...", "2": "diff --git b/..."}
```

Then score with a code-review question:

```bash
v2-score --candidates diffs.json \
  --question "Is this the best code change? Judge correctness, minimality, and risk." \
  --threshold 0.05 \
  --ledger ledger.jsonl
```

Jev grades the **diff**, so candidates can diverge on real implementations
and the winner ships the strongest change — not the best-sounding
description of one. Broken hunks can be rejected before anything touches
the tree: validate with `git apply --check` before scoring.

## Why patches, not prose

- The judge sees what will actually land in the repo.
- Diffs double as the audit trail the protocol ledger needs.
- A candidate that writes beautiful prose about a broken change loses to
  an ugly diff that works — which is the correct outcome.
- `git apply --check` is a free pre-filter: unparseable diffs never
  reach Jev.

## Limits

- Jev judges the diff text, not a test run. Pair patch-grading with
  `tests/` for anything load-bearing.
- Large diffs cost more to score; keep candidate scopes tight.
- Same weaknesses as prose mode apply (see README.md): no quality floor,
  hot batch p's, single judge.
