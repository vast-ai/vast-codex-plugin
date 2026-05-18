---
description: First-time Vast.ai setup — store API key, register SSH key, verify auth
argument-hint: [api-key]
---

First-time setup for the Vast.ai CLI. Runs the three onboarding steps documented in the `vastai` skill's Quick Start.

## Steps

1. **Store the API key.** If `$1` is non-empty, treat it as the API key and run:
   ```
   vastai set api-key "$1" --raw
   ```
   If `$1` is empty, ask the user for their key from <https://cloud.vast.ai/account> and run the same command.

2. **Register an SSH key BEFORE the first instance launch.** Read `~/.ssh/id_ed25519.pub` (preferred) or `~/.ssh/id_rsa.pub`. If neither exists, instruct the user to run `ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519` and re-invoke. Once a key is found, register it:
   ```
   vastai create ssh-key --ssh-key "$(cat <path-to-pub-key>)" --raw
   ```
   Launching an instance before registering a key produces an unreachable host — this step is critical.

3. **Verify authentication.** Run:
   ```
   vastai show user --raw
   ```
   On success, report the user's email and current balance. On `401 Unauthorized`, suggest re-running with a fresh API key.

## Notes

- All `vastai` invocations include `--raw` so the response is parseable JSON.
- The full command reference, image catalog, and error table live in the `vastai` skill (`~/.agents/skills/vastai/SKILL.md`).
