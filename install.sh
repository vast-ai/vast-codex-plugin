#!/usr/bin/env bash
# install.sh — install the Vast.ai Codex plugin into the user's home dirs.
#
# - Skill   → ~/.agents/skills/vastai/SKILL.md           (preferred, auto-invokes on Vast intents)
# - Prompts → ~/.codex/prompts/vast-{setup,status,cost,search,launch}.md  (explicit /prompts:vast-*)
#
# Idempotent: re-running upgrades in place. Pass --force to overwrite without prompts.
# Pass --dry-run to print what would happen.

set -euo pipefail

FORCE=0
DRY=0
while (("$#")); do
  case "$1" in
    --force) FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: install.sh [--force] [--dry-run]"
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$REPO/skills/vastai"
PROMPTS_SRC="$REPO/prompts"

SKILL_DST="$HOME/.agents/skills/vastai"
PROMPTS_DST="$HOME/.codex/prompts"

run() {
  if [[ $DRY -eq 1 ]]; then echo "[dry-run] $*"; else eval "$@"; fi
}

require_no_clobber() {
  local target="$1"
  [[ -e "$target" && $FORCE -eq 0 ]] || return 0
  echo "refusing to overwrite $target (pass --force to allow)" >&2
  exit 1
}

echo "Installing vast-codex-plugin from $REPO"
echo "  skill  → $SKILL_DST"
echo "  prompts → $PROMPTS_DST/vast-*.md"
echo

# Skill
run "mkdir -p '$SKILL_DST'"
require_no_clobber "$SKILL_DST/SKILL.md"
run "cp '$SKILL_SRC/SKILL.md' '$SKILL_DST/SKILL.md'"
echo "✓ skill installed"

# Prompts
run "mkdir -p '$PROMPTS_DST'"
for f in "$PROMPTS_SRC"/vast-*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  require_no_clobber "$PROMPTS_DST/$base"
  run "cp '$f' '$PROMPTS_DST/$base'"
  echo "✓ prompt installed: /prompts:${base%.md}"
done

echo
echo "Done. Restart your Codex session (CLI or IDE extension) to pick up the new files."
echo "Verify: \`ls $SKILL_DST $PROMPTS_DST\`"
