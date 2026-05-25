# Multi-Agent Orchestration

A portable Claude Code bundle: one skill + five subagents that coordinate a multi-step change as a DAG of parallel PRs. Repo-agnostic.

## What's inside

```
multi-agent-orchestration/
├── .claude-plugin/plugin.json
├── agents/                                   # subagents (pinned model/effort/isolation)
│   ├── mao-planner.md
│   ├── mao-builder.md
│   ├── mao-designer.md
│   ├── mao-reviewer.md
│   └── mao-audit.md
├── skills/multi-agent-orchestration/         # the skill
│   ├── SKILL.md
│   └── references/
│       ├── planning-protocol.md
│       ├── design-protocol.md
│       ├── environment.md
│       ├── deviations-and-progress.md
│       └── templates.md
├── install.sh                                # symlinks contents into ~/.claude/{agents,skills}/
└── README.md
```

## Install

### On this machine (already done if you cloned + ran install)

```bash
./install.sh
```

The script creates symlinks:

- `~/.claude/agents/mao-*.md` → `<bundle>/agents/mao-*.md`
- `~/.claude/skills/multi-agent-orchestration` → `<bundle>/skills/multi-agent-orchestration`

After installation Claude Code discovers both the skill and the agents on next session start.

### On a new machine

1. Clone or copy this folder to wherever you keep tools (e.g. `~/.claude/plugins/local/multi-agent-orchestration/`).
2. From inside the folder, run `./install.sh`.
3. Done. The agents and the skill are now available in any Claude Code session on that machine.

### Uninstall

```bash
./install.sh --uninstall
```

Removes the symlinks. The bundle files are untouched.

## How to use

The skill is documented in [`skills/multi-agent-orchestration/SKILL.md`](skills/multi-agent-orchestration/SKILL.md). Two modes:

- **Planning:** `create multi-agent-orchestration-plan for <description>` — fires the `mao-planner` subagent in an isolated worktree; it ships a PR with a `plan.md`.
- **Execute:** `execute multi-agent-orchestration for <path>` — the coordinator (your chat session) reads the merged plan and dispatches builders / designers / reviewers / audit, all as isolated-worktree subagents.

## Configuration

All five subagents pin `model: opus`, `effort: xhigh`, and `isolation: worktree`. Edit the agent files directly to override.

## License

Not currently licensed. Personal use.
