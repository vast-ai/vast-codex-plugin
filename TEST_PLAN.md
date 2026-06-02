# Test plan for `fix(skills,prompts)` — vast-codex-plugin

Prompts to paste into a fresh codex chat to verify the CLI-correction PR. Each row is one prompt and the response criterion. No shell scripts — just chat in, response out.

A full automated runbook lives in `TESTING.md`; this is the minimal delta for *this* PR.

## Setup

1. Restart codex (so it picks up the patched skills + prompts).
2. Open a fresh chat. Confirm the prompts are listed:

   ```
   /prompts:vast-setup    /prompts:vast-status    /prompts:vast-cost
   /prompts:vast-search   /prompts:vast-launch
   ```

## Phase 1 — Knowledge probes (paste in chat)

| # | Prompt | PASS criterion |
|---|---|---|
| 1.1 | *What URL do I go to to create a Vast.ai API key?* | Response says `console.vast.ai/manage-keys/`. FAIL on `cloud.vast.ai/account`. |
| 1.2 | *Show me the command to register `~/.ssh/id_ed25519.pub` with vastai.* | Command uses **positional** pubkey: `vastai create ssh-key "$(cat ~/.ssh/id_ed25519.pub)"`. FAIL on `--ssh-key` flag. |
| 1.3 | *What image should I use to launch a Vast instance if I don't have a specific one in mind?* | Response says `vastai/pytorch:@vastai-automatic-tag`. FAIL on `pytorch/pytorch:@vastai-automatic-tag`. |
| 1.4 | *Why do people say to always pass `--cancel-unavail` when launching on Vast?* | Mentions silent-stopped state, fail-fast, or scheduler parking the request. |
| 1.5 | *I have a 6000-character onstart-cmd and the instance never starts. What's wrong?* | Mentions the API `400/3471 Invalid args: len(args) > N` error as the source of truth for the limit, plus a gzip+base64 or `--onstart FILE` workaround. PASS if it still names "4048" but also mentions reading the live cap. |
| 1.6 | *vastai is rejecting my search filter `compute_cap>=70`. What's going on?* | Explains the encoding is `cuda_cap * 100`, so CUDA 7.0+ → `compute_cap>=700`. |
| 1.7 | *Schedule 4 hours of maintenance on machine 12345 starting tomorrow at 9am UTC.* | Command uses `--sdate <unix-epoch> --duration 4 --maintenance_category`. FAIL on `--start-date 2026-…T09:00:00Z` or `--duration "4h"`. |
| 1.8 | *Defrag machines 100, 200, 300.* | Command is `vastai defrag machines 100 200 300`. FAIL on `vastai defragment machines …`. |

## Phase 2 — Slash-prompt walkthrough

For each prompt, invoke it in chat and watch the shell calls codex makes.

| # | Invocation | PASS criterion |
|---|---|---|
| 2.1 | `/prompts:vast-setup` (no arg) | Tells you to grab the key from `console.vast.ai/manage-keys/`. When registering the SSH key, the command uses **positional** pubkey (no `--ssh-key` flag). |
| 2.2 | `/prompts:vast-cost` | Spend-rate call is `vastai show instances-v1 --raw -a` (NOT bare `--raw`). Invoices call uses `--limit <N> --latest-first`. |
| 2.3 | `/prompts:vast-status` | List call is `vastai show instances-v1 --raw -a` (NOT bare `--raw`). |
| 2.4 | `/prompts:vast-launch OFFER=<some-offer-id>` | Create command includes **all of** `--ssh --direct --cancel-unavail --raw`. Image defaults to `vastai/pytorch:@vastai-automatic-tag`. After success, codex runs `vastai show instance <id> --raw` once to confirm materialization. |
| 2.5 | *Launch the cheapest spot/interruptible RTX 3090 with a bid of $0.10/hr.* | Command includes `--bid_price 0.10`. FAIL on `--bid 0.10` or `--bid-price 0.10`. |

## Phase 3 — Host-skill routing

| # | Prompt | PASS criterion |
|---|---|---|
| 3.1 | *List my Vast.ai hosted machines.* | Loads `vastai-host` skill (not `vastai`). Runs `vastai show machines --raw`. On 401, suggests checking permission scope with `vastai show api-keys --raw` — NOT "reset api-key". |
| 3.2 | *What's the going hourly rate for RTX 4090s in US datacenters per Vast.ai's marketplace metrics?* | Runs `vastai metrics gpu` (or `metrics gpu-locations`) with **flag-shaped** args, not a query expression. |

## Pass threshold

15 prompts total. ≥14/15 to ship. Re-test any failures after a fix.

Budget: $0 (no instance launches in this delta). Run `TESTING.md` phase 3 if you also want a live launch.
