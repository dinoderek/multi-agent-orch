# Planning protocol — how to produce a `plan.md`

This is the playbook for **planning mode**. The `mao-planner` subagent follows it to turn a user intent into a planning artifact (one `plan.md` index plus one file per task under `tasks/`) shipped as a reviewable PR.

The planner runs in an **isolated worktree** so multiple plans can be drafted in parallel. That isolation also means the planner cannot ask the user mid-flight; the coordinator gathers any clarifying detail upfront, hands the planner a complete spec, and the user reviews the resulting PR.

## Two participants — coordinator and planner

**Coordinator (you, in chat):**

1. Captures the user's intent.
2. Asks any clarifying questions needed BEFORE dispatching the planner.
3. Resolves enough of the repo config block to seed the planner's prompt.
4. Dispatches `mao-planner` via the Agent tool.
5. When the planner returns, surfaces the PR URL to the user.
6. On re-dispatch (user asked for changes), re-invokes the same planner with the existing PR URL referenced.

**Planner (`mao-planner` subagent):**

1. Loads the skill's reference docs and the repo's CLAUDE.md / AGENTS.md / docs/specs/**.
2. Locks down plan-level outcomes first.
3. Explores the codebase, drafts the DAG, hunts for design tasks, sizes tasks, adds the final test card.
4. Writes plan.md (the index) and tasks/<id>.md (per task), opens the PR.
5. Returns the PR URL to the coordinator.

## Invocation

Planning mode enters on one of:

- `create multi-agent-orchestration-plan for <description>`
- `create multi-agent-orchestration-plan at <path> for <description>`
- `plan this as multi-agent-orchestration`

When the user provides a `<path>`, the planner uses it. Otherwise the planner picks `docs/plans/<plan-slug>/plan.md` and logs the choice in the PR body for the user to confirm.

## Plan outcomes are the most important thing to nail

Everything else flows from the plan's outcomes:

- **Tasks exist to satisfy outcomes.** Every task ultimately maps back to at least one plan outcome. If a task doesn't, it shouldn't be in the plan.
- **The final test card directly tests the outcomes.** It's the contract with the human; the planner sets the bar by writing the outcomes well.
- **Audit verifies outcomes were delivered.** Vague outcomes mean an audit that can't conclude pass/fail.

What makes a good plan outcome:

- **Observable.** A reader can tell whether it's true by looking at the system, not at the code.
- **Specific.** "Sync works" is not an outcome. "POST /api/sync returns `{cursor, applied: number}` for a valid batch in < 500ms; conflicting writes return 409 with `{conflicts: SyncConflict[]}`" is.
- **Testable.** The final test card can assert it.
- **Bounded.** No "and the system is robust" weasel-phrases. If you can't test "robust", it's not an outcome.

The planner spends real time on outcomes before drafting tasks. If outcomes shift after task cards are written, you've wasted work.

## What the coordinator gathers before dispatching

A complete planner prompt includes:

- **Intent:** what the user wants to build (verbatim or restated).
- **Plan path:** if specified, else "default".
- **Repo config hints:** integration branch (if non-`main`), host, host-access mechanism, quality-gate command (if known).
- **Constraints the user volunteered.**
- **Scope boundary:** explicit out-of-scope if the user mentioned it.

The coordinator does NOT explore the codebase before dispatching — that's the planner's job.

If the user is vague ("plan something for the sync engine"), the coordinator asks 1–2 short clarifying questions in chat, gets answers, then dispatches.

## Outputs

A single PR landing this directory structure:

```
<plan-root>/
  plan.md                 # the index — goal, outcomes, orchestration, DAG, task list, deviations log
  tasks/
    t1.md                 # one file per task
    t2.md
    …
    tN.md                 # the final test card (mandatory; see below)
```

`designs/` does NOT exist yet — designers create those at execute time.

PR title: `[plan] <plan-name>`. PR body explains the plan in human terms.

The user reviews via the PR. After merge, they invoke `execute multi-agent-orchestration for <plan-path>`.

## Planner workflow (inside the worktree)

### 1. Restate the goal

In the PR body's Summary section, restate the user's intent in one paragraph.

### 2. Lock down the plan outcomes

This is the load-bearing step. Write the `## Outcomes` block before anything else. Each outcome observable, specific, testable, bounded. If you can't write a clean outcome, the intent isn't clear enough — log the ambiguity in the PR body and continue with your best guess, but flag it loud.

These outcomes drive the final test card (step 8) and the audit. Treat them as the contract you're signing with the user on their behalf.

### 3. Resolve the repo config block

Per `references/environment.md`. The coordinator's prompt seeded some; infer the rest. If genuinely ambiguous, pick the most-canonical option and log the choice in the PR body's `## Deviations from card` section.

### 4. Explore the codebase

Read enough to know constraints. Use Read, Grep, Glob freely; spawn `Explore` subagents if available.

You're looking for: existing patterns to compose with, contracts touched, prior decisions, risk areas.

You are NOT trying to figure out the implementation. Surface-level only.

### 5. Draft a coarse DAG

3–10 task nodes is the sweet spot. If you're at 15+, your granularity is probably wrong — but check against the size rule (step 7) before assuming so.

The DAG is the only source of truth for dependencies.

### 6. Hunt design tasks — be aggressive

For every node, ask: "Could two reasonable builders ship materially different things from this card?" If yes → design task or design task in front of it.

**Granularity rule for design tasks: ONE question per design task = ONE decision.** Two questions = two tasks. See `references/design-protocol.md`.

### 7. Size and split — task = 1 PR

**Each build task is ONE PR sized at ≤ ~2000 added or modified lines.** Deletions don't count toward the budget (a refactor that removes 5000 lines and adds 200 is fine — reviewers digest the additions). Tests count.

If a build task estimates over ~2000 added lines, **split it**. Common splits:
- Foundation + integration: ship the new module in one PR, wire it up in the next.
- By feature surface: each independent feature is its own task.
- By layer: data layer task, API layer task, UI layer task.

Design tasks naturally fit (doc-only, < 200 lines). The size rule binds builds.

After sizing, the DAG may have more nodes. That's correct. Bigger DAG ≠ worse plan; un-reviewable mega-PRs ≠ better plan.

### 8. Add the final test card — mandatory

Every plan ends with a test card that verifies the plan-level outcomes end-to-end. This card is the sink of the DAG (every other task is a dependency).

The final test card:

- **Type:** `build` (it ships test code).
- **Title:** typically `verify plan outcomes` or similar.
- **Problem:** state what's being verified.
- **Inputs:** every other task merged (the coordinator enforces by DAG).
- **Outcomes:**
  - For each plan-level outcome, an automated test asserts it.
  - Tests run in the repo's CI / quality gate.
  - Failing the test card surfaces a real outcome miss, not a flaky test.
- **Output artifact:** the test file path(s).
- **Out of scope:** anything that's not testing the plan outcomes (don't bundle unrelated work).

If the plan has genuinely untestable outcomes (rare — pure-doc plans, or plans whose outcome is "deleted the dead code"), the planner may omit the test card BUT must explicitly justify in the PR body's `## Deviations from card` section. Default: include it.

The audit step later checks that the final test card's tests actually exercise each plan outcome — a hand-wave test ("there's a smoke test") that doesn't map to outcomes is rejected by audit.

### 9. Write the task files

One file per task under `tasks/<id>.md`. Use the task-card template from `references/templates.md`. Every field concrete:

- **Type:** `build` or `design`.
- **Problem:** one paragraph.
- **Inputs:** dep task ids and specific files/sections expected to exist at start. For tasks downstream of a design, cite `designs/<design-id>.md ## Decision` as binding (the doc will be the canonical source once the designer ships).
- **Outcomes:** observable, specific, testable. Map back to plan outcomes when applicable.
- **Output artifact:** files/paths/symbols. Coordinator verifies post-merge.
- **Out of scope:** explicit boundaries.

Do NOT add: status fields, implementation hints, sketched decisions for downstream design tasks. Cards stay thin pointers; design docs (once they land) are canonical.

### 10. Write plan.md as the index

Keep it short. Use the template from `references/templates.md`. Sections:

- **Goal** (one paragraph)
- **Outcomes** (from step 2 — this is the most important block)
- **Orchestration** (the resolved repo config)
- **DAG** (mermaid)
- **Tasks** (list with links to `tasks/<id>.md` and a one-line title each; type marked)
- **Deviations log** (empty placeholder)

`plan.md` does NOT contain the cards themselves. Cards live in `tasks/`.

### 11. Open the PR

PR title: `[plan] <plan-name>`. PR body uses the four-section template; Standard checklist's quality-gate / tests fields are usually `N/A` for a doc-only PR. List any ambiguities resolved in `## Deviations from card`.

### 12. Return

One line to the coordinator: PR URL + one-sentence summary.

## Granularity self-check (planner runs this before opening the PR)

- [ ] Every plan outcome is observable, specific, testable, bounded.
- [ ] Every task maps back to at least one plan outcome.
- [ ] Every build task is sized ≤ ~2000 added/modified lines (deletions don't count).
- [ ] Every design task answers exactly ONE question = produces ONE decision.
- [ ] The final test card exists and tests each plan outcome (or is explicitly justified as omitted).
- [ ] Every dependency in the DAG is justified by a hand-off artifact one task produces and the next consumes.
- [ ] Cards do not duplicate content from design docs (designs aren't written yet, but downstream cards must cite `designs/<id>.md`).
- [ ] No task is so trivial that orchestration overhead exceeds the work.
- [ ] Plan-level `## Outcomes` are covered by the union of task outcomes.

If any fails, revise BEFORE opening the PR.

## User review and iteration

Three outcomes:

- **Merge as-is** — user invokes `execute multi-agent-orchestration for <plan-path>` next.
- **Comment with revisions** — user adds review comments. Coordinator re-dispatches `mao-planner` with the PR URL referenced; planner updates the same branch and pushes.
- **Close the PR** — plan is abandoned.

The coordinator does NOT auto-re-dispatch on PR comments — only when the user explicitly asks ("revise the plan", "fix and re-push", etc.).

## Anti-patterns

- **Dispatching the planner with a vague brief.** "Plan something for the sync engine" → garbage in. Clarify first.
- **Vague plan outcomes.** "System is robust" / "Performance is good" — untestable, so the audit can't confirm them.
- **Coordinator exploring the codebase before dispatching.** That's the planner's job.
- **One giant build task.** Project, not a task. Size rule enforces.
- **Skipping the final test card.** Default-on, off only with explicit justification.
- **Zero design tasks on a plan that touches new contracts.** Builders won't figure it out.
- **Designs that bundle two questions.** One decision per design.
- **Vague `Output artifact`.** Without it, the DAG is decorative.
- **Cards that restate what designs will decide.** Cards point; design docs are canonical (once they exist).

## Handing off to execute mode

When the user invokes `execute multi-agent-orchestration for <path>`, the coordinator (possibly a new chat session) reads the merged plan fresh, derives state from the host, and begins dispatching. The plan must be complete on its own — a plan that depends on chat context is broken.
