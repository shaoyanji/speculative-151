# speculative-151

**v2 1-N-1 speculative decoding**: 1 orchestrator → N parallel stateless
candidate subagents → Jev `noul` scores each → argmax of the score JSON ships
straight to the response, unfiltered. No grader, no decider.

This repo makes the pattern replicable: a declarative TOON spec, a scaffold
CLI, a scorer, guardrails, tests, and an honest accounting of where the
pattern breaks.

## The shape

```
1 orchestrator
  → N parallel stateless candidates (default 5, min 2, max 25)
    → 1 Jev noul batch (one API call, scores all N)
      → argmax(score JSON) → response verbatim, unfiltered
```

Mirrors LLM speculative decoding: cheap draft candidates generated in
parallel, a verifier pass picks the winner. Linear chain-of-thought commits
to one trajectory early, so a wrong turn compounds; 1-N-1 keeps multiple
hypotheses live and collapses only after evidence arrives.

## What this is NOT

This is **not** separation-of-concerns parallelism. Do not use it as "one
subagent for the db, one for the frontend." There is crossover work by
design — every candidate answers the *same* prompt with a different
variable (tone, length, angle).

The strength is twofold:

1. **Multiplying model strength.** Five independent reads of one prompt
   cover more of the answer space than one read. Jev then picks the best —
   best-of-N with an explicit, calibrated selection step.
2. **Core-agent token efficiency.** The orchestrator stays thin: it pipes
   prompts out and relays the winner back. The declarative TOON spec keeps
   the protocol dense (a few dozen tokens per dispatch) instead of five
   full prompt contexts bloating the core window. Clean prompts beat
   polluted context.

It plays well for Muse as one chat window at a time: the orchestrator never
holds the whole fan-out in its context — candidates are stateless, the
prompt is their whole world.

## Quickstart

```bash
# 1. scaffold the dispatch spec (TOON: headers + one row per slot)
bin/v2-scaffold --prompt "Why is the sky blue?" --slots 5

# 2. dispatch: spawn one subagent per row with its expanded_prompt
#    (agent-runtime work — see "Agent contract" below)

# 3. collect responses -> candidates.json, then score
bin/v2-score --candidates candidates.json --ledger ledger.jsonl
# -> {"raw_scores":{"1":0.81,...},"grades":{"1":1.0,...},"scores":{"1":0.81,...},
#     "winner":1,"margin":0.08,"threshold":0.05,"decision":"SHIP"}

# 4. argmax ships: the winner's text goes to the response verbatim.
#    If decision is NO_RESULT (exit 3), do NOT ship — re-run or merge.
```

`candidates.json` format (either works):

```json
[{"slot": 1, "text": "..."}, {"slot": 2, "text": "..."}]
{"1": "...", "2": "..."}
```

Pure JSON scaffold output for pipelines:

```bash
bin/v2-scaffold --prompt "..." --json | jq '.rows'
```

## Dependencies

| Dependency | Why | Required |
|---|---|---|
| `bash` ≥ 4 | all tooling | yes |
| `jq` | JSON parsing everywhere | yes |
| `jevq` (`~/bin/jevq`) | Jev System One scoring (TypeSafe) | yes, for `v2-score` |
| `timeout` (coreutils) | bound the Jev call | yes, for `v2-score` |
| `sha256sum` (coreutils) | prompt hashing for ledger | yes |
| `git` | repo itself; `git apply --check` for patch mode | recommended |
| `csvq` | query TOON/CSV rows | optional |
| `python3` | only if you prefer the `jevq` stdlib path directly | optional |

Jev auth: the credential is already stored for `~/bin/jevq` (connector
`custom.typesafe`). Never paste keys; see `~/workspace/skills/jev/SKILL.md`.

## Tools

- **`bin/v2-scaffold`** — emits the dispatch spec. Flags: `--prompt` (required,
  ≤ 8000 chars), `--variables` (default `brief,technical,humor,minimal,blunt`),
  `--slots` 2–25 (default 5; N=1 rejected — nothing to judge), `--template`
  (scaffold file; placeholders `{SLOT} {VAR} {VAR_UPPER} {PROMPT} {FRAGMENT}`),
  `--json` (pure JSON). TOON output embeds a `# json:` line parseable via
  `grep '^# json: ' | sed 's/^# json: //' | jq .`
- **`bin/v2-score`** — scores candidates with one `jevq --batch` call.
  The grader stage is independent: its own timeout (default 120s, TERM then
  hard-KILL 10s later), exit 4 on failure, and candidate-generation
  timeouts never cascade into it — scoring proceeds with the candidates
  that finished (≥ 2 required). The raw unmodified Jev p's are captured
  first (stderr, `--scores-out`, ledger) before any grade multiplication
  or threshold logic. Kelly split: final rank = Jev p × `--grades`
  multiplier (each grade in (0,1], default 1.0); the discrimination
  threshold (default 0.05) applies to the final scores: top-two gap below
  it → `NO_RESULT`, exit 3. Emits
  `{"raw_scores":..,"grades":..,"scores":..,"winner":..,"margin":..,
  "threshold":..,"decision":..}`; `--ledger` appends the audit line
  (raw scores AND decision, always).
- **`bin/v2-ledger`** — appends one JSONL audit line (prompt sha, never the
  prompt) to the protocol ledger.
- **`lib/guardrails.sh`** — shared validation: slot range, prompt length,
  variable names, threshold range, prompt hashing.
- **`lib/toon.sh`** — TOON parse helpers: `toon_rows`, `toon_json_rows`,
  `toon_header`, `toon_table_names`.
- **`spec/v2-1-5-1.toon`** — the canonical declarative spec. Data, not
  prose: a runner can read a row, strip indent, `jq` the fields, and spawn
  the slot without interpreting anything.
- **`docs/PARALLEL_EDITS.md`** — git-patch mode: candidates emit unified
  diffs, Jev grades the diff.

## Agent contract

The orchestrator:

1. Runs `v2-scaffold` to get the dispatch spec.
2. Spawns one **stateless** subagent per row, piping only the row's
   `expanded_prompt` — no shared context, no history.
3. Collects the N response texts into `candidates.json`.
4. Runs `v2-score`. On `SHIP`, delivers the winner's text **verbatim,
   unfiltered**. On `NO_RESULT`, re-runs with sharper variables or merges —
   never crowns a tie.
5. Makes no tool calls itself beyond routing; produces no words of its own.

Subagents: the prompt is the whole world. If the orchestrator needs memory,
a subagent fetches it and returns it in its report — memory is just another
subagent call.

## The discrimination threshold

Batch-mode Jev p's run systematically **hot** — treat them as upper bounds,
not gospel. When the top two scores land within `--threshold` (default
0.05), the judge cannot actually discriminate: ship nothing, exit 3, and
either re-run with sharper contrasting variables or merge the finalists.
Crowning noise as "the right answer" is the most common way this pattern
lies to you.

## Scoring: Kelly split (p from Jev, b from the grade)

Final rank score per candidate = **Jev p × grade**, split like the Kelly
criterion: Jev provides the gut probability, a separate grade provides the
multiplier (the b risk-discount, net odds).

- **p comes only from Jev.** The raw, unmodified `noul` probability per
  candidate — the first preference — is captured before anything else
  touches it: printed to stderr, written to `--scores-out`, and stored in
  the ledger alongside the final decision. It is never recomputed or lost
  to downstream adjustments.
- **b comes only from the grade.** Each grade is a number in (0,1],
  derived from additional factors *outside* Jev: discrimination-margin
  history, candidate timeout history, test/verification results
  (`git apply --check`, test suites), cost/latency budgets. It is never
  sourced from Jev — p and b are never mixed at the source.
- Without `--grades`, every grade defaults to 1.0: pure Jev ranking.

```bash
bin/v2-score --candidates candidates.json \
  --grades '{"1":0.9,"2":0.7}' \
  --scores-out raw.json \
  --ledger ledger.jsonl
# -> {"raw_scores":{"1":0.81,...},"grades":{"1":0.9,...},"scores":{"1":0.729,...},
#     "winner":1,"margin":0.06,"threshold":0.05,"decision":"SHIP"}
```

The grader stage is independent: it has its own timeout (default 120s,
hard-kill 10s after TERM) and exits 4 on failure — candidate-generation
timeouts never cascade into scoring, which proceeds with the candidates
that finished (minimum 2). See `CONSTRAINTS.md`.

## Weaknesses (read before trusting this)

1. **No quality floor.** Jev picks the best of N, but if all N are bad, the
   protocol ships the least-bad one wearing calibrated probabilities.
   There is no "none of the above" — failure gets a veneer of statistical
   legitimacy.
2. **The judge grades its own drafts.** The same model family writes the
   candidates and scores them. It can pick the least-bad draft; it can
   never inject ground truth it doesn't have. "Process over content" is
   the thesis *and* the weakest point — the process is self-referential.
3. **Hot batch p's.** Per the Jev skill docs, batch-mode probabilities run
   systematically high. Discount before any Kelly math; the ranking is more
   trustworthy than the absolute numbers.
4. **Single judge, single point of failure.** One stateless scoring pass;
   a thin question or a malformed batch silently produces noise. Nothing
   in the base protocol detects judge error or triggers a re-judge.
5. **Cost.** Every message costs ~N candidate generations plus a scoring
   pass. A 15-1 validation run picked the same winner as 3-1-1 at ~3× the
   spend. 1-N-1 is a *quality* shape, not a cheap one — use the max-slots
   cap and the warn threshold.
6. **Latency.** Stages are sequential: candidates → score → ship. A hung
   candidate used to block everything; the fan-out stage still needs its
   own per-candidate timeout, but the grader stage is now independent —
   it has its own bounded timeout (TERM then hard-KILL, exit 4) and never
   waits on candidate generation. Document the degraded path (judge
   proceeds with the candidates that returned).
7. **"Only subagent voices speak" is load-bearing theater.** The
   orchestrator authors every prompt, picks every variable, frames every
   question — it is the author of everything while claiming authorship of
   nothing. "Statelessness" doesn't remove polluted context; it relocates
   it to the piping decisions.
8. **Anchoring.** If candidates can see each other's roles (neighbor
   peeking) or a speculative pre-draft, independence collapses: they
   anchor, converge, and the judging space shrinks to perturbations of one
   idea instead of N independent reads.
9. **Dual-track contradictions.** Scoring long-form and short main-idea
   summaries in separate noul spaces can crown different winners. Decide
   *before* running which track ships, or you have two answers and no
   protocol.
10. **Not for decomposed work.** Parallel db/frontend-style splits need
    coordination, shared state, and ordering — the opposite of stateless
    candidates. Use this pattern for *judgment* (which answer is best),
    not for *division of labor*.
11. **Grade gaming.** Whoever sets the `--grades` controls the outcome:
    a grade of 0.1 on the Jev favorite silently crowns the runner-up, and
    nothing in the protocol distinguishes a principled risk discount from
    a thumb on the scale. Grades are a second judgment surface — log them
    in the ledger (done automatically), keep the raw Jev p's visible
    (done automatically), and treat any grade < 1.0 as a claim that needs
    its own audit trail: which factor, measured how.

What converts the pattern from theater to something real: thresholds that
can return NO_RESULT, an audit ledger so "trust the process" is checkable
rather than ceremonial, and failure rules that bound the damage. Trust has
to be verifiable, not declared.

## Tests

```bash
bash tests/test_scaffold.sh
```

Covers: N=1/0 rejected, N=26 rejected, N=2 and N=25 accepted, empty/missing
prompt rejected, bad variable names rejected, TOON header + row counts,
embedded JSON parses, header adapts to slots, `--json` mode, template
substitution, prompt hashed (never echoed), variable cycling.

## Layout

```
speculative-151/
├── README.md            # this file
├── CONSTRAINTS.md       # operational rules: independent grader, raw-first scores, Kelly split
├── spec/v2-1-5-1.toon   # canonical declarative spec
├── bin/v2-scaffold      # dispatch-spec CLI (TOON/JSON)
├── bin/v2-score         # jevq batch scorer + argmax + threshold gate
├── bin/v2-ledger        # audit ledger appender
├── lib/guardrails.sh    # validation: slots, prompt, variables, threshold
├── lib/toon.sh          # TOON parse helpers
├── templates/default.tmpl
├── examples/demo.sh     # end-to-end canned demo
├── tests/test_scaffold.sh
└── docs/PARALLEL_EDITS.md  # git-patch mode for code changes
```
