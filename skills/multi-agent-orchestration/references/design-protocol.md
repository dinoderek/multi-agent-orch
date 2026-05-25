# Design task protocol

Design tasks resolve uncertainty *before* it poisons downstream build tasks. They sit at the front of the DAG (or fan out from a parent that discovers ambiguity). This file is the full spec.

Read this whenever:
- You're about to dispatch a `Type: design` task.
- You're reviewing a design task's PR.
- A build task's reviewer reports "the card is ambiguous about X" — that's a signal to retro-add a design task.

## The design doc is the canonical artifact

The design doc at `designs/<task-id>.md` is the **single source of truth** for what the design decided. Downstream task cards do not duplicate its content — they **point** to it.

Why this matters: duplicated content drifts. If a card restates the decision and the design later gets corrected, you have two versions of "what to do" and builders will follow the wrong one. Single source of truth + cards-as-pointers means correcting the design doc is enough; no card sweep needed.

In practice:

- Downstream cards reference the design doc under their `Inputs` field: `Inputs: t1 merged; binding contract in designs/t1.md ## Decision`.
- The marker `> Updated from <design-id>: see designs/<id>.md ## Decision` on a card is a *pointer* — not a restatement of what the design decided.
- The design doc's `## Downstream impact` section lists which cards now reference it.

## The granularity rule — one question per design task

**Each design task answers exactly one question.** If a design would need to answer two questions to unblock its downstream, it must be split into two design tasks.

Why this matters: downstream builders read ONE design's `## Decision` section and treat it as a binding contract. A doc with two decisions forces the builder to figure out which applies to their card — and they will get it wrong some of the time. Two decisions = two cards.

Examples:

- ❌ "Design the auth subsystem" — that's a subsystem, not a question.
- ❌ "Decide the session token storage AND the refresh strategy" — two questions.
- ✅ "Decide where session tokens are stored" — one question, one decision.
- ✅ "Decide how session tokens refresh" — separate question, separate task. Often runs in parallel.

When in doubt, split. A design task is one PR with one doc; the overhead is trivial. An ambiguous build task is a wasted builder turn plus re-review plus possibly a do-over.

## Design writing guidelines

Designers MUST follow these. Reviewers reject docs that don't.

1. **Always present alternatives + rationale.** ≥ 2 options enumerated, even if one is obviously winning. The rationale for *not picking* the alternatives is as important as the rationale for picking the winner — it's what future-you and the next maintainer need to evaluate whether the decision still holds.

2. **No code, no implementation detail.** Designs solve specific, hard, *design* questions — they don't sketch implementations. The exception: a 2–5 line type signature, function shape, or schema fragment is fine when it's genuinely the quickest way to express a contract. Don't sketch a 30-line implementation to "show how it would work" — that's the build task's job, not yours. If you find yourself reaching for code, ask: am I solving the design question, or am I just writing the build? If the latter, stop.

3. **Be succinct. Do not repeat yourself.** State each thing once. Constraints listed in `## Constraints` are not also restated in `## Options considered`. If you're tempted to recap, link — `(see Constraints)`.

4. **Go for the simplest solution.** When you've picked an option, ask: can this be made simpler? If yes, simplify and ask again. Stop when further simplification would lose the property that made the option viable. The simplest correct solution wins ties.

5. **Short, descriptive output.** A design doc is typically < 200 lines. If you find yourself with deep dives, exploration logs, or long discussions you don't want to lose, put them in linked documents under `designs/<task-id>-notes/` and reference them from the main doc. The main doc must remain skimmable in 2–3 minutes — that's what makes it useful as a contract.

## When to make something a design task

Use a design task instead of a build task when **any** of:

- The "right" approach is genuinely unknown — there are 2+ plausible options with non-obvious tradeoffs.
- The change touches a contract (data schema, API surface, public interface, file/symbol path) that downstream tasks all depend on.
- Existing code patterns conflict and a winning convention needs to be picked before fanout.
- The investigation needed to scope a build task is itself non-trivial (more than ~30 min of reading).

Heuristic: **if you can't write the build task's `Outcomes` section without hedging, it's a design task.** If two reasonable builders could ship materially different things from the same card and both believe they were correct, it's a design task.

## Inputs the designer needs

The card must specify, concretely:

- **The question** — one sentence. "Which layer owns idempotency: client cache or server upsert?" not "figure out sync."
- **The downstream tasks blocked by this** — by task id. The designer knows what their decision needs to enable.
- **Known constraints** — what's already decided and not up for grabs (e.g., "Postgres, no new dependencies, must preserve existing public API").
- **Pointers to relevant existing code/docs** — file paths, prior decisions. Don't make the designer go rediscover them.
- **Decision authority** — who breaks ties? Default: the designer recommends; the human (in PR review) decides if there's disagreement.

Without these, the designer either over-investigates (slow) or under-investigates (wrong call). The coordinator should refuse to dispatch a design task with a vague question — push back to refine the card first.

## Steps the designer follows

The designer's PR must show their work. The expected shape:

1. **Restate the question** — one paragraph. Catches misunderstandings early.
2. **Survey the territory** — read the cited code/docs, plus anything discovered. Note assumptions and constraints.
3. **Enumerate options** — at least 2. For each: one short paragraph + key tradeoffs (perf, complexity, blast radius, reversibility). Per the writing guidelines, no code unless a type signature is the shortest way to convey a contract.
4. **Decide.** Pick one. Justify in terms of constraints. Tiebreaker: smallest blast radius, easiest to reverse.
5. **Update downstream cards to reference the doc.** Edit cards inline with the pointer marker `> Updated from <task-id>: see designs/<task-id>.md ## Decision`. Do NOT restate the decision in the card. Update the card's `Inputs` field to cite the design doc.
6. **Note open questions** — anything out of scope. Becomes follow-up tasks or notes, not blockers.

## Outputs the designer produces

A design PR lands:

1. **`<plan-root>/designs/<task-id>.md`** — the design doc, structure below.
2. **Pointer-only edits to downstream task cards** in `plan.md` (or `tasks/`) — `> Updated from <task-id>: see designs/<task-id>.md ## Decision` markers, plus `Inputs` field updates that cite the doc. **Cards do not restate the design's content.**
3. *(Optional)* a linked-notes directory `designs/<task-id>-notes/` containing detailed explorations the main doc references but doesn't inline.

### `designs/<task-id>.md` structure

Keep it short. Linked notes for deep dives, not in this file.

```markdown
# Design: <title>

## Question
<one paragraph restatement>

## Constraints
- <bullet list — concise>

## Options considered
### Option A: <name>
<one short paragraph; tradeoffs as a tight bullet list>

### Option B: <name>
…

## Decision
<chosen option + the one or two reasons that made it the winner; why the alternatives lose, briefly>

## Downstream impact
- <task-id>: card updated to reference this doc.
- <task-id>: card updated to reference this doc.

## Open questions / follow-ups
- <anything out of scope>

## Linked notes (optional)
- [Detailed exploration of perf tradeoff](<task-id>-notes/perf.md)
```

## Acceptance criteria

A design task is "done" (ready for reviewer approval) when:

- [ ] `designs/<task-id>.md` exists with the required sections.
- [ ] At least one downstream card has been updated with a pointer to the doc (under `Inputs` or via a `> Updated from <task-id>:` marker), OR the doc explicitly states no card updates are needed and why. **No card restates the design's content.**
- [ ] The decision is one of the enumerated options — no surprise third option in `## Decision`.
- [ ] ≥ 2 options were enumerated. Single-option designs are an opinion in disguise — reject.
- [ ] Constraints from the card appear in the design doc's `## Constraints`.
- [ ] No build code changed in this PR. Design tasks are doc-only.
- [ ] Exactly one `## Decision` section. Two decisions = should have been split during planning; reviewer rejects and the plan is fixed.
- [ ] Doc is reasonably short — typically < 200 lines. Long discussions live in `designs/<task-id>-notes/` and are linked from the main doc.
- [ ] No prose duplication. Each fact stated once.
- [ ] No code blocks beyond ≤ 5-line type signatures / schema fragments used as the tightest expression of a contract.

Reviewers check these specifically.

## Hand-off to downstream builders

When the coordinator dispatches a build task whose card was refined by a design task, the subagent prompt MUST explicitly reference the design doc:

> Your binding contract is `designs/<design-task-id>.md` — the `## Decision` section. Do not re-relitigate. If you disagree, log it in the PR's `## Deviations from card` section; the reviewer will decide.

The downstream card itself already points to the doc (per step 5 above). The prompt reinforces.

## Anti-patterns

- **Restating the design in cards.** Cards point to the doc; the doc is canonical. Two copies = inevitable drift.
- **Designs that bundle questions.** Two `## Decision` sections = two design tasks crammed into one. Reviewer rejects.
- **Designs that don't update cards.** Builders inherit the same ambiguity the design was supposed to resolve.
- **Designs that turn into builds.** If the designer writes implementation, stop and split. Design PRs that include implementation hide their reasoning.
- **Single-option designs.** An opinion in disguise. Push back.
- **Designs without a question.** If the doc opens with "let's think about X" instead of restating a specific question, the designer didn't understand what they were solving. Reject.
- **Long docs.** > 200 lines almost always means the designer mixed exploration with the decision. Move exploration to linked notes; keep the main doc skimmable.

## Researching with the host MCP / web tools

Designers have full tool access in their worktree:
- Read repo code and docs liberally.
- Use `WebFetch` / `WebSearch` for external references when relevant.
- Use `mcp__context7__*` for library documentation when available — materially better than relying on training data for API surfaces.

A well-cited design doc makes the reviewer's job easier and the decision more durable. Encourage citations; don't accept hand-wave references.
