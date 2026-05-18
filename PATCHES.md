# Local patches to vendored SKILL.md

This file mirrors the patches kept in `vast-ai/vast-claude-plugin/PATCHES.md` — every plugin repo vendors the same SKILL.md from `vast-ai/vast-cli` and carries the same local deltas until the patches land upstream.

## 1. "Critical rules for agents" section near top

**Why:** T1.3 routing corpus on the Claude plugin surfaced two failures rooted in SKILL.md prominence, not content gaps:

- **R-09** ("kill instance 12345") — agent ran `vastai destroy instance 12345` without `-y`, triggered the confirmation prompt.
- **R-23** ("set HF_TOKEN to hf_xxxxx as an env var") — agent produced zero tool calls; skill didn't auto-load on env-var prompts.

**Upstream proposal:** PR to `vast-ai/vast-cli` adding the 5-rule section verbatim. Upstream PR link will be added here once filed.

## 2. Broadened `description:` frontmatter + beefed-up Environment Variables section

**Why:** Skill auto-loading on env-var / token / billing prompts; richer prompt-to-call examples for `HF_TOKEN`, `OPENAI_API_KEY`, and `--raw` on every call.

## Re-vendoring procedure

When upstream merges the patches:
1. Re-vendor `skills/vastai/SKILL.md` from the new upstream SHA.
2. If the patches are still missing, re-apply manually.
3. Update `VENDORED_FROM.md`.

Keep this file in sync across the three plugin repos.
