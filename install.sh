#!/usr/bin/env bash
# Symlinks the multi-agent-orchestration bundle's agents and skill into
# ~/.claude/agents/ and ~/.claude/skills/ so Claude Code discovers them.
#
# Usage:
#   ./install.sh             install (or refresh) the symlinks
#   ./install.sh --uninstall remove the symlinks
#
# Idempotent. Safe to re-run. Does not touch any other files in those dirs.

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$BUNDLE_DIR/agents"
SKILL_SRC="$BUNDLE_DIR/skills/multi-agent-orchestration"

USER_AGENTS_DIR="${CLAUDE_HOME:-$HOME/.claude}/agents"
USER_SKILLS_DIR="${CLAUDE_HOME:-$HOME/.claude}/skills"

ACTION="${1:-install}"

ensure_dir() {
  mkdir -p "$1"
}

link_one() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    local existing
    existing="$(readlink "$dest")"
    if [[ "$existing" == "$src" ]]; then
      echo "  ok    $dest (already linked)"
      return
    fi
    echo "  warn  $dest exists and points to $existing — replacing"
    rm "$dest"
  elif [[ -e "$dest" ]]; then
    echo "  ERROR $dest exists and is not a symlink. Move or delete it first." >&2
    exit 1
  fi
  ln -s "$src" "$dest"
  echo "  link  $dest -> $src"
}

unlink_one() {
  local dest="$1"
  if [[ -L "$dest" ]]; then
    rm "$dest"
    echo "  rm    $dest"
  fi
}

case "$ACTION" in
  install)
    echo "Installing multi-agent-orchestration symlinks…"
    ensure_dir "$USER_AGENTS_DIR"
    ensure_dir "$USER_SKILLS_DIR"

    echo "agents:"
    for f in "$AGENTS_SRC"/mao-*.md; do
      [[ -e "$f" ]] || { echo "  ERROR no mao-*.md files in $AGENTS_SRC" >&2; exit 1; }
      link_one "$f" "$USER_AGENTS_DIR/$(basename "$f")"
    done

    echo "skill:"
    link_one "$SKILL_SRC" "$USER_SKILLS_DIR/multi-agent-orchestration"

    echo "Done. Restart any open Claude Code session for the agents to load."
    ;;
  --uninstall|uninstall)
    echo "Uninstalling multi-agent-orchestration symlinks…"
    echo "agents:"
    for f in "$AGENTS_SRC"/mao-*.md; do
      [[ -e "$f" ]] || continue
      unlink_one "$USER_AGENTS_DIR/$(basename "$f")"
    done
    echo "skill:"
    unlink_one "$USER_SKILLS_DIR/multi-agent-orchestration"
    echo "Done. Bundle files are untouched."
    ;;
  *)
    echo "Usage: $0 [install|--uninstall]" >&2
    exit 2
    ;;
esac
