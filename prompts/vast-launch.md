---
description: Launch a Vast.ai instance from an offer ID with sane defaults (PyTorch image, --ssh --direct)
argument-hint: OFFER=<id> [IMAGE=<image>] [DISK=<gb>] [LABEL=<str>]
---

Launch a Vast.ai GPU instance from an offer ID with renter-friendly defaults.

## Steps

1. **Parse `$ARGUMENTS`** as named pairs: `OFFER=<id> [IMAGE=<image>] [DISK=<gb>] [LABEL=<str>]`. `OFFER` is required; everything else has a default. Reject if `OFFER` is missing.

2. **Ensure an SSH key is registered BEFORE launching.** Critical regression: launching without a registered key produces an unreachable instance.
   ```
   vastai show ssh-keys --raw
   ```
   If the response is `[]`, register the user's default key first:
   ```
   vastai create ssh-key --ssh-key "$(cat ~/.ssh/id_ed25519.pub)" --raw
   ```
   Fall back to `~/.ssh/id_rsa.pub` if no ed25519 key exists.

3. **Build the create command** with defaults:
   - `--image` → `$IMAGE` or `pytorch/pytorch:@vastai-automatic-tag`
   - `--disk` → `$DISK` or `20`
   - `--label` → `$LABEL` or `codex-launch-$(date +%s)`
   - Always include `--ssh --direct --raw`

4. **Run it:**
   ```
   vastai create instance $OFFER --image <IMAGE> --disk <DISK> --label <LABEL> --ssh --direct --raw
   ```

5. **Parse the response.** Success returns `{"success": true, "new_contract": <INSTANCE_ID>}`. Report the new instance ID and tell the user to poll with `vastai show instance <INSTANCE_ID> --raw` or invoke `/prompts:vast-status <INSTANCE_ID>`.

6. **Error paths:**
   - `Insufficient credits` → surface the billing link; don't retry.
   - Offer no longer rentable → tell the user to re-run `/prompts:vast-search` and pick another.

## Critical regressions (don't drop)

- `--ssh --direct` is required for a usable SSH connection.
- `--raw` on the create call (so `new_contract` can be parsed).
- SSH key registered *before* launch (step 2).
- Default image must fall back to `pytorch/pytorch:@vastai-automatic-tag` — never ask the user for an image if they didn't specify one.
- Don't auto-destroy the new instance from this prompt, even if it fails to launch — that's `/prompts:vast-status` + an explicit destroy step territory.

## Notes

- Full flag reference + image catalog: `vastai` skill § "Instances".
