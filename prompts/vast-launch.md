---
description: Launch a Vast.ai instance from an offer ID with sane defaults (PyTorch image, --ssh --direct --cancel-unavail)
argument-hint: OFFER=<id> [IMAGE=<image>] [DISK=<gb>] [LABEL=<str>]
---

Launch a Vast.ai GPU instance from an offer ID with renter-friendly defaults.

## Steps

1. **Parse `$ARGUMENTS`** as named pairs: `OFFER=<id> [IMAGE=<image>] [DISK=<gb>] [LABEL=<str>]`. `OFFER` is required; everything else has a default. Reject if `OFFER` is missing.

2. **Ensure an SSH key is registered BEFORE launching.** Critical regression: launching without a registered key produces an unreachable instance.
   ```
   vastai show ssh-keys --raw
   ```
   If the response is `[]`, register the user's default key first (public key is **positional** — no `--ssh-key` flag):
   ```
   vastai create ssh-key "$(cat ~/.ssh/id_ed25519.pub)" --raw
   ```
   Fall back to `~/.ssh/id_rsa.pub` if no ed25519 key exists.

3. **Build the create command** with defaults:
   - `--image` → `$IMAGE` or `vastai/pytorch:@vastai-automatic-tag` (the `@vastai-automatic-tag` scheme only resolves on Vast-curated images — `pytorch/pytorch:@vastai-automatic-tag` will fail)
   - `--disk` → `$DISK` or `20`
   - `--label` → `$LABEL` or `codex-launch-$(date +%s)`
   - Always include `--ssh --direct --cancel-unavail --raw`

4. **Run it:**
   ```
   vastai create instance $OFFER --image <IMAGE> --disk <DISK> --label <LABEL> --ssh --direct --cancel-unavail --raw
   ```
   `--cancel-unavail` tells the scheduler to fail fast instead of silently parking the request in a `stopped` state when the host can't accept it. Without it you get a phantom instance accruing nothing visible until you `show instance` and notice.

   For **interruptible (spot) offers**, swap on-demand for a bid: replace `--ssh` defaults with `--bid_price <USD/hr>` (matching the offer's `min_bid` or higher). The rest of the flag set is the same.

5. **Parse the response.** Success returns `{"success": true, "new_contract": <INSTANCE_ID>}`. Immediately run `vastai show instance <INSTANCE_ID> --raw` once to confirm the instance materialized (the success response means "request accepted", not "instance running"). Report the new instance ID and tell the user to poll with `vastai show instance <INSTANCE_ID> --raw` or invoke `/prompts:vast-status <INSTANCE_ID>`.

6. **Error paths:**
   - `Insufficient credits` → surface the billing link; don't retry.
   - Offer no longer rentable → tell the user to re-run `/prompts:vast-search` and pick another.

## Critical regressions (don't drop)

- `--ssh --direct --cancel-unavail` is the required connection-mode trio. Dropping `--cancel-unavail` is the common silent-failure mode.
- `--raw` on the create call (so `new_contract` can be parsed).
- SSH key registered *before* launch (step 2).
- Default image must fall back to `vastai/pytorch:@vastai-automatic-tag` (NOT `pytorch/pytorch:@vastai-automatic-tag` — the automatic-tag scheme only resolves on Vast curated images). Never ask the user for an image if they didn't specify one.
- Don't auto-destroy the new instance from this prompt, even if it fails to launch — that's `/prompts:vast-status` + an explicit destroy step territory.

## Notes

- Full flag reference + image catalog: `vastai` skill § "Instances".
