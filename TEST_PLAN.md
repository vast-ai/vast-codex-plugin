# Test plan — vast-codex-plugin

How to verify the plugin against a live Vast.ai account. Prompts live in `TEST_PROMPTS.txt`. This file describes setup, what to look for, and pass criteria. A separate `TEST_PLAN_2.md` covers focused re-tests for the most recent skill fixes.

## Setup

```bash
cd /Users/will/freelance/work/vast-plugins/workspace/repos/vast-codex-plugin
./install.sh --force
```

That copies `skills/vastai/SKILL.md` → `~/.agents/skills/vastai/SKILL.md` and the five prompts → `~/.codex/prompts/`. The host skill isn't part of `install.sh` — copy it manually so the host-routing prompts work:

```bash
mkdir -p ~/.agents/skills/vastai-host
cp skills/vastai-host/SKILL.md ~/.agents/skills/vastai-host/SKILL.md
```

Pre-flight:

```bash
echo "${VAST_API_KEY:?must export VAST_API_KEY first}"   # set BEFORE launching codex
vastai --version                                          # 1.0.13+
```

Restart codex. In a fresh chat, confirm the prompts loaded:

```
/prompts:vast-setup    /prompts:vast-status    /prompts:vast-cost
/prompts:vast-search   /prompts:vast-launch
```

## What good looks like

A passing run shows the agent reads from the skill and uses the correct CLI shapes without retrying or paraphrasing:

- **Correct flags first try.** Positional args where the docs say positional; underscores vs hyphens matching the actual command.
- **No invented commands.** Agent never types `vastai show templates`, `vastai bid`, or similar non-existent subcommands.
- **Surfaces server responses.** On 4xx/5xx, agent quotes the body verbatim and suggests a concrete next step (check scope, check deposit, upgrade CLI), not "let me retry."
- **Destructive ops gated.** Rule #12 (`create team` rebinds API key context) fires before the agent runs it.

A failing run reaches for `--ssh-key`, `--bid`, `pytorch/pytorch:@vastai-automatic-tag`, `cloud.vast.ai/account`, or runs `create team` without confirmation.

## Coverage areas (cross-reference `TEST_PROMPTS.txt`)

Walk through `TEST_PROMPTS.txt` top to bottom. The prompts are grouped roughly by area:

1. **Setup & auth** — API key URL, SSH key registration (positional pubkey contents).
2. **Search** — hidden default overrides, `compute_cap` encoding (`cuda_cap * 100`), structured template queries.
3. **Launch** — Vast-curated default image, `--ssh --direct --cancel-unavail`, materialization re-check, `--bid_price` for spot offers at or above `min_bid`.
4. **Instance ops** — `show instances-v1 -a` (auto-paginate), `ssh` via parsed `ssh-url`, label/change-bid positional/flag forms.
5. **Templates** — `--disk_space` (not `--disk`), `search templates` for discovery, `delete template --template-id <numeric>`.
6. **Teams & account** — Rule #12 confirmation before `create team`, role lookup before `invite member`, env-vars treated as write-only.
7. **Host routing** — host-side intents load `vastai-host` skill; 401 attributed to scope, not key reset.

Slash invocations at the end of `TEST_PROMPTS.txt` exercise `/prompts:vast-setup`, `/prompts:vast-cost`, `/prompts:vast-status`, `/prompts:vast-search`.

## Real-instance prep

Several prompts need real values. Before pasting them:

```bash
# Real offer for a launch prompt
vastai search offers 'num_gpus=1 rentable=true verified=true' -o 'dph_total' --raw --limit 5 | jq -r '.[].id'

# Real instance(s) for label/ssh/status prompts
vastai show instances-v1 --raw -a | jq -r '.instances[] | {id, label, gpu_name, actual_status}'

# Real spot instance for change-bid prompt (launch one first if you don't have one)
```

Substitute the real values for `<OFFER_ID>`, `<INSTANCE_ID>`, `<SPOT_INSTANCE_ID>`, `<TEMPLATE_ID>`, `<TEMPLATE_HASH>`, `<ENDPOINT_ID>`.

## Cleanup

```bash
vastai show instances-v1 --raw -a | jq '.instances[] | .id'   # any leftovers?
vastai destroy instance <id> -y
```

## Pass threshold

Walk through the file end to end. The skill is solid if each prompt either lands the right command or correctly refuses (e.g., `create team` should refuse without explicit confirmation; HF_TOKEN reveal should explain env-vars are write-only).

Budget: a few dollars max if you fire the launch prompts; near-zero if you skip launches.

## When something fails

The skill is the runbook. If the agent does the wrong thing, it's a skill bug — fix the relevant section in `skills/vastai/SKILL.md` (or `skills/vastai-host/SKILL.md`) and re-run the failing prompt. After a skill edit, run `./install.sh --force` and restart codex so the new content loads.
