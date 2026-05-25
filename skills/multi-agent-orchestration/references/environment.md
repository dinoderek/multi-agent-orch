# Environment — what this skill expects

This skill is repo-agnostic, but it assumes a specific shape of working environment. Verify these once at coordinator start; if anything is missing, surface it before dispatching the first task.

## Required

1. **Git repository** with a long-lived integration branch (typically `main`, sometimes `develop` or `trunk`). The plan's `## Orchestration` block declares which.
2. **PR-based git host** reachable from this session — GitHub, GitLab, Gitea, Bitbucket. The host must support:
   - Listing PRs by title prefix or label.
   - Reading PR reviews and commits.
   - Opening, updating, and commenting on PRs.
   - Merging (human-only — the coordinator never merges).
3. **Host access mechanism** — one of, in order of preference:
   - **GitHub MCP** server (`mcp__github__*`) — preferred when available; surfaces clean structured PR data. Note: in this session, these tools may be deferred; load via `ToolSearch` once at coordinator start.
   - **`gh` CLI** (GitHub) or **`glab`** (GitLab) — fallback. Builders/reviewers shell out from their worktree.
   - **Raw git push + manual PR opening** — NOT supported by this skill. If neither MCP nor a host CLI is available, fall back to direct execution and tell the user.
4. **Subagent worktree isolation** — the harness must support `isolation: "worktree"` on Agent calls. Without it, parallel builders share working tree and corrupt each other. Verify by spawning one trivial Agent with `isolation: "worktree"` before the first real dispatch; abort if it errors.
5. **A quality-gate command the builder can run inside its worktree** — repo-specific. The plan declares it. Examples: `./scripts/quality-fast.sh`, `pnpm run check`, `make test`, `cargo check && cargo test`, `bun run typecheck && bun test`. If the repo has no such command, mark the gate as `N/A` in the plan and document why.

## Optional but valuable

- **Worktree-isolated dependency install** — for JS/TS monorepos especially, each worktree should have its own `node_modules` (or equivalent). Without per-worktree installs, parallel builders thrash a shared cache. If the repo doesn't already enforce this (e.g., via a `.claude/worktrees/` placement and lockfile-aware install), surface it as a risk in the first status message.
- **CI on the integration branch** — gives reviewers an objective signal beyond local gate runs. The skill does not require CI but reviewers should weight it when available.
- **Issue tracker integration** — if the host links PRs to issues, the audit step can verify outcome coverage faster.
- **Robust project context provided in the root CLAUDE.md or equivalent** - plans and task cards do not provide project-specific context. We assume solid project specific context such as development guardrails, testing patterns, development patterns, etc are provided in the repository.

## Repo config block — resolve once per plan

The first time you enter orchestrator mode for a given plan, resolve these values and confirm with the user if any are ambiguous. They get stamped into the plan's `## Orchestration` section so future iterations and resumed sessions all see the same config.

| Key | Source | Default if absent |
| --- | --- | --- |
| `plan-root` | plan path itself | `docs/plans/` |
| `plan-slug` | from plan's `## Orchestration` | derive from plan dir name |
| `integration-branch` | repo convention (`git symbolic-ref refs/remotes/origin/HEAD`) | `main` |
| `host` | `git remote -v` parsing | ask the user |
| `host-access` | tool presence check | MCP if available, else CLI |
| `quality-gate-cmd` | repo `README` / `package.json` scripts / `Makefile` | ask the user |
| `builder-concurrency` | plan override | `4` |
| `reviewer-concurrency` | plan override | unbounded |
| `model` | plan override | `opus` (Opus 4.7, high effort) |

When ambiguous (e.g., the repo has both `make test` and `pnpm test`), ask the user explicitly — don't guess. A wrong gate command silently lets failing PRs through.

## Adapting to repo-specific specs

Many repos have their own `docs/specs/**`, `CONTRIBUTING.md`, or `AGENTS.md` describing testing strategy, documentation conventions, and review standards. The orchestration protocol does not replace these — it composes with them:

- Builders read the relevant repo specs as well as the task card.
- Reviewers cite repo specs when requesting changes (`per docs/specs/testing.md §3`).
- The Standard checklist's "Docs / spec updates per repo conventions" line is where this composition surfaces.

If the repo has nothing of the sort, leave that checklist line as `N/A` and proceed.

## Degraded modes

If a requirement is missing, you may continue in a degraded mode *only* with the user's acknowledgment:

- **No worktree isolation:** serialize builders (concurrency = 1). Reviewers still parallel-safe because they're read-mostly.
- **No GitHub MCP, only `gh`:** every host operation becomes a shell call from builder/reviewer/coordinator. Slower but functional.
- **No quality-gate command:** mark gate as `N/A`; reviewers compensate with stricter manual review. Surface this as a risk in audit.

If two or more requirements are missing, recommend direct execution instead — the overhead of orchestrating exceeds its value.
