# Align all CLI claims with actual vastai behavior

## Summary

- Imported verified skill content from the equivalent `vast-claude-plugin` patches (commits `ab7d6eb` + `87f182c`), where every documented `vastai` subcommand was audited against `vastai <cmd> --help`, the `vast.py` source, and live runs on GTX 1080-class hosts. ~50 flag/syntax corrections across renter and host skills.
- Replaced server-enforced constants (arg-length cap, `compute_cap` threshold, `--limit` page sizes) with pointers to live sources of truth, so the skill doesn't go stale when the server bumps a value.
- Ported the factual corrections into the 4 affected Codex prompts (`vast-setup`, `vast-launch`, `vast-cost`, `vast-status`), preserving the existing `$1` / named-pair argument syntax and frontmatter. `vast-search` already matched verified behavior.

## CLI corrections

**Renter skill — flag/syntax:**
- `create api-key`, `create team-role`: `--permission_file` / `--permissions` take a **file path**, not inline JSON
- `create-team` is hyphenated with `--team-name` (not `create team --name`)
- `invite member`: `--role`, not `--role-id`
- `create subaccount`: `--type` is `host`/`client`; `--username` + `--password` required
- `tfa activate`: `CODE` is positional, `--secret` + `-t` required
- `label instance`, `prepay instance`: positional value, not `--label` / `--amount`
- `change bid`: `--price` (not `--bid` / `--bid_price`)
- `show env-vars`: `-s` / `--show-values` needed to reveal values
- `search templates` / `search invoices`: structured query, not free text
- `create workergroup`: identified by template+endpoint, no `--name` flag
- `create template`: `--disk_space` (not `--disk`)
- `update template`: positional is `HASH_ID` string
- `delete template`: no positional; use `--template-id` or `--hash-id`
- `run benchmarks`: `--template_hash` and `--gpus` (plural)
- `update workergroup`: `--endpoint_id` is required
- `detach ssh`: numeric IDs only (pubkey-string crashes server-side)
- `cancel copy`: positional accepts `instance:/path` form
- `vastai execute`: only `ls`/`rm`/`du`, and only on stopped instances
- `ssh-url --raw` returns plain `ssh://root@host:port` string, not JSON
- `--latest-first` is `invoices-v1` only, not `instances-v1`

**Renter skill — new rules / error mappings:**
- `compute_cap` encoding: `cuda_cap * 100`; derive threshold from `vastai search offers --help` rather than baking the value in
- `VAST_API_KEY` precedence + admin-key shadowing warning
- 2FA-required 401 mapped to `vastai tfa login`
- SSH-fail diagnostic rule: pull `vastai logs <id>` BEFORE any retry, destroy, or relaunch — sshd rejection reason is only in logs
- `--onstart-cmd` arg-length cap: read from the API 400/3471 `Invalid args: len(args) > N` error when it fires (rather than baking the literal limit)

**Host skill — cross-cutting + host-specific:**
- `schedule maint`: `--sdate` (unix epoch) + `--duration` (hours float) + `--maintenance_category`, not `--start-date` ISO8601 / `--duration "4h"`
- `add network-disk`: positional `MACHINES` + `MOUNT_PATH` + `-d disk_id`, not `--cluster` / `--size` / `--machine`
- Removed nonexistent `remove network-disk` subcommand
- `metrics gpu*` take flags, not query expressions
- `list machine`: `--price_min_bid` (not `--price_min`)
- `show machines` does not paginate; the gotcha applies only to `invoices-v1`
- `defrag machines`: subcommand is `defrag machines` even though its own `--help` usage line reads `vastai defragment machines IDs` (verified empirically — `defragment` returns `invalid choice` at the parser)

**Codex prompts:**
- `vast-setup.md`: `console.vast.ai/manage-keys/` URL (not `cloud.vast.ai/account`); `create ssh-key` takes positional pubkey, not `--ssh-key` flag; shell-history warning for `$1`-passed keys
- `vast-launch.md`: `--cancel-unavail` mandatory; default image `vastai/pytorch:@vastai-automatic-tag` (not `pytorch/pytorch` — the automatic-tag scheme only resolves on Vast curated images); positional `create ssh-key`; `--bid_price` flow for interruptible offers; materialization check via `show instance` after success response
- `vast-cost.md`, `vast-status.md`: `-a` on `show instances-v1` / `--limit <N>` on `show invoices-v1` to short-circuit the interactive pagination prompt that fires under `--raw`; `--latest-first` noted as invoices-v1 only

Verified end-to-end via launch → poll → ssh → `nvidia-smi` → destroy runs on two GTX 1080-class hosts in the source `vast-claude-plugin` branch, plus targeted smoke tests for each newly-corrected flag invocation.
