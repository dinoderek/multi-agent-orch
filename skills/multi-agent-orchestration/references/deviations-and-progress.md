# Progress tracking, deviations, and orchestrator consistency

Multi-agent plans fail in slow motion. A single dropped outcome, a stale card the builder loaded before it was updated, a "merged but no hand-off artifact", a parallel pair of designs that contradict each other — none of these explode immediately, but compounded across a dozen tasks they leave the plan in a state nobody can audit. This file defines the discipline that prevents that.

## Three distinct things to track

Don't conflate them:

- **Progress** — what has moved since last iteration. Derived from the host every iteration. Ephemeral in memory; logged to `status.md` for human-readable history.
- **Deviations** — what shipped *differently* from what was planned. Persistent; lives in the plan's `## Deviations log` (one line per merged PR) and as pointer markers on affected task cards.
- **Consistency** — the plan as a whole still makes sense after parallel work lands. This is the orchestrator's active responsibility; it's not derived, it's checked.

## Plan vs. task edits — keep plan.md stable

`plan.md` is the index — goal, outcomes, orchestration block, DAG, task list, deviations log. It is the user's commitment; treat it as mostly stable.

Individual task cards live in `tasks/<id>.md`. That's where deviation pointers, refinement markers, and design-doc references get written. The bar for editing `plan.md` is: "does a pending task still have the right context?" If yes, leave `plan.md` alone and propagate updates to the task files. If no, update `plan.md` (typically: add a follow-up task, add a DAG edge, refine an outcome).

This split exists because plan.md is loaded by every subagent at dispatch and read by the audit; churning it costs context and creates merge conflicts. Task files churn freely without that cost.

| Type of update | Where it goes |
| --- | --- |
| Deviation pointer to a merged PR | `tasks/<downstream-id>.md` (as `> Updated from <id>: see …` marker) |
| Refinement of a pending card's `Inputs` / `Output artifact` | `tasks/<id>.md` directly |
| New follow-up task discovered mid-plan | new `tasks/<new-id>.md` + add link in `plan.md` task list + DAG edge |
| Plan-outcome refinement | `plan.md` `## Outcomes` (rare — surface to user first) |
| Per-merge log line | `plan.md` `## Deviations log` |
| Iteration log entry | `status.md` |

## `status.md` — mandatory orchestrator log

Every plan has a `status.md` at the plan root. The orchestrator appends one entry per iteration. Template in `references/templates.md`. Example entry:

```
## 2026-05-25 14:30 — iteration 7
- Dispatched: t3 (builder), t4 (reviewer)
- Merged this iter: t1 (no deviation)
- Stuck: t5 (4 iter, awaiting human merge of t2)
- Notes: parallel designs t6 + t7 both merged this iter; consistency check passed — t6's decision doesn't conflict with t7's.
```

Why mandatory: (a) resumed sessions read it to reconstruct what happened; (b) the audit consults it; (c) it's the primary debugging artifact when a plan goes sideways. Without it, post-mortems are guesswork.

Keep entries short. The deviations log carries semantic facts; status.md carries the timeline.

## Per-iteration state diff

Each coordinator iteration produces an in-memory snapshot. Rebuilt every iteration from the host — you don't need to persist it (status.md captures the human-readable version).

For each task in the plan:

| Field | How to compute |
| --- | --- |
| state | from host: `pending` / `open` / `needs-review` / `approved` / `merged` |
| pr_url | from host, when state ≠ pending |
| last_event | timestamp of latest PR commit or review |
| iterations_stuck | counter — increment if state is unchanged since last iteration AND no human-action pending |
| handoff_verified | bool — only meaningful for `merged` state |

The state diff is `{ tasks where state changed since last iteration }` ∪ `{ tasks where iterations_stuck >= 3 }`.

After dispatch, post a one-line status to the user AND append the same line to `status.md`:

```
Dispatched: t3 builder, t4 reviewer. Merged: t1 (no deviation). Stuck: t5 (4 iter, awaiting human merge of t2).
```

## Hand-off verification

When a task moves to `merged`, immediately verify the hand-off artifact promised by its `Output artifact` field exists. Don't wait for the dependent task to discover the problem.

| Task type | Verify |
| --- | --- |
| Build | Files listed in `Output artifact` exist on the integration branch at the merge SHA. |
| Design | `<plan-root>/designs/<task-id>.md` exists; the doc has exactly one `## Decision` section; at least one downstream `tasks/<id>.md` references the doc (under `Inputs` or via a `> Updated from <task-id>: see designs/<task-id>.md` pointer marker). Cards MUST NOT restate the design's content — that's drift. If a card duplicates content, treat the hand-off as failed and surface. |
| Final test card | `Output artifact` test files exist; the test file content references the plan-level outcomes (the audit will do a deeper check). |

If verification fails:

1. Do NOT mark `handoff_verified: true`.
2. Do NOT dispatch dependent tasks.
3. Post a `[coordinator]` comment on the merged PR describing the gap.
4. Surface to the user. Log the gap in `status.md`.

## Consistency check — especially after parallel designs

**Whenever two or more design tasks merge in the same iteration, the orchestrator runs an explicit consistency check before dispatching dependents.** This is the most common failure mode for parallel multi-agent plans: two designers, working independently, decide things that contradict.

The check:

1. **Read each newly-merged design doc's `## Decision`.** Concretely, not just titles.
2. **For each pair of fresh designs**, ask: do their decisions compose? Common conflicts:
   - Both touch the same contract (e.g., a function signature) with incompatible shapes.
   - One implies a constraint the other ignores.
   - Their respective downstream cards point at the same file with different expectations.
3. **For each design + each pending downstream card**, re-read the card and check: does the design's decision invalidate any of the card's outcomes or out-of-scope clauses?

If conflicts found:
- Do NOT dispatch the affected downstream tasks.
- Surface to user with a one-paragraph summary of the conflict, the affected docs and cards, and your recommendation.
- Possible resolutions (user decides): revise one design, add a reconciliation design task, or amend the affected downstream cards by hand.
- Log the conflict and resolution in `status.md`.

If no conflicts, log in `status.md`:
```
Notes: parallel designs t6 + t7 both merged this iter; consistency check passed — no conflicts.
```

This check also runs (less critically) for single-design merges, but parallel is where it's load-bearing.

## Deviation logging — every merge, every time

After **every** merge:

1. **Append to `plan.md` `## Deviations log`** — one line:
   ```
   - <task-id> (PR #N, merged YYYY-MM-DD): <one-line summary; "none" if no deviation>
   ```
   Log it even when there's no deviation — this gives a complete merge history.

2. **Propagate deviations that affect pending cards.** Same pointer convention as design hand-off: the card POINTS to where the deviation is documented (the merged PR's body), it doesn't restate it.
   ```markdown
   > Updated from t1: see PR #N's `## Deviations from card` — auth-init export was renamed; downstream imports must update.
   ```
   Keep the pointer one line. The PR is canonical for the deviation specifics; the card is the breadcrumb.

3. **Do NOT edit in-flight cards.** Their subagent loaded the old contract; mid-flight edits create incoherent PRs. Append a follow-up task and a DAG edge instead.

4. **For deviations that touch `plan.md` `## Outcomes`** — surface to the user before continuing. Plan-level outcomes are the contract with the human; the orchestrator does not silently mutate them.

## Distinguishing deviation severity

- **Trivial** (rename, comment, internal helper shape) — log it, no card updates needed.
- **Contract-affecting** (function signature, file path, schema field) — log + propagate pointers to affected task cards + verify hand-off artifact still matches.
- **Outcome-affecting** (the merged PR doesn't fully satisfy its outcomes, or it satisfies them in a way that prevents another outcome elsewhere) — log + surface immediately + likely follow-up task.

Reviewers should reject outcome-affecting deviations, but some only become visible after merge. When the coordinator notices one post-merge, treat it like a dispute: stop fanning out, surface.

## In-flight task discipline

A task is "in-flight" from dispatch until merge.

- **Don't edit its card.** Above.
- **Don't re-dispatch on a transient host error.** Retry the host query, not the whole subagent.
- **Do re-dispatch on `Verdict: CHANGES_REQUESTED`.** Pass the reviewer comment as context.
- **Watch `iterations_stuck`.** ≥ 3 → surface. Common cause: human-action needed that nobody noticed (CI flake, dep merge, ambiguity).

## Resumption (new chat, same plan)

When a new session starts with `execute multi-agent-orchestration for <path>`:

1. Read `plan.md` fresh.
2. Read `status.md` to reconstruct what happened in prior sessions — the iteration log is your only carry-over.
3. Re-derive all state from the host — do NOT trust any in-memory state from prior sessions.
4. The `## Deviations log` is your audit trail. If incomplete (prior session crashed mid-merge), reconstruct from merged PRs' commit messages and add the missing entries before dispatching.
5. Re-verify hand-off artifacts and re-run the consistency check for any designs merged in the last logged iteration before dispatching new work. A previous session may have skipped the check.

## Audit's view of all this

The audit subagent reads `plan.md`, `status.md`, the deviations log, hand-off artifacts, the final test card's tests, and PR history. Its job:

- Outcomes from `## Outcomes` are each tested by the final test card. Vague tests rejected.
- Deviation entries don't contradict plan outcomes.
- Missing hand-off artifacts on merged tasks.
- `status.md` entries span the plan's execution (a gap means a session lost work).
- Pending or in-flight tasks at audit time = audit shouldn't be running yet — surface.

Treat `status.md` and the deviations log as load-bearing artifacts. The audit cannot do its job without them.
