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

## Follow-up fixes from live codex testing (2026-06-02)

The initial audit was against `vastai <cmd> --help` + the `vast.py` source — both correct as references but unable to catch CLI bugs that only surface at runtime. A live test run against a real Vast.ai account surfaced 9 additional issues. Each was patched in the commits below.

**Removed entirely:**

- **`vastai execute` is currently CLI-broken.** Even a correctly-formed `vastai execute <id> 'ls -la /workspace'` against a stopped instance crashes with `AttributeError: 'str' object has no attribute 'get'` (with or without `--raw`). The earlier audit had documented its `ls`/`rm`/`du` allow-list and stopped-only restriction — both still apply on paper, but the command returns no useful output today. The skill no longer recommends it; the "Logs & exec" section was renamed to "Logs" and a one-liner steers agents away in case they rediscover `execute` from `vastai --help`. (`b654dfb`)

**Replaced silently-wrong skill claims:**

- **`create ssh-key` takes pubkey CONTENTS, not a path.** The CLI silently accepts any string and stores the literal "/path/to/file" text — no error, but no client matches. Skill examples now use `"$(cat ~/.ssh/id_ed25519.pub)"`.
- **`show invoices-v1` requires `-c` or `-i`** (charges or invoices). The bare form fails. Skill no longer leads with the bare example and now prefixes the billing section with the requirement.
- **`vastai copy` doesn't work on stopped instances either.** The in-instance rsync daemon isn't running, so `vastai copy <id>:/path ./local` fails with `rsync: Unknown module '<id>'`. Combined with the `execute` crash, **there is NO working way to inspect a stopped instance's files** — agent must `start instance`, wait for `running`, then SSH or copy.

**Documented version skew / gotchas surfaced by the live run:**

- **`create-team` subcommand naming.** Newer CLIs accept hyphenated `create-team`; older CLIs use `create team`. Skill now tells the agent to check `vastai --help | grep -E 'create[ -]team'` and try the other form on parser rejection.
- **`invite member --role <name>`** returns HTTP 500 on unknown roles. Roles are team-defined, not a fixed enum. Skill now requires `vastai show team-roles` first.
- **`run benchmarks --endpoint_name`** must match `[a-z0-9_-]+`. Dots, slashes, spaces fail with API 400 `Value error, contains disallowed shell characters`.
- **`create workergroup`, `create api-key`** require admin-scope keys — scoped/read-only keys return HTTP 403 and 400 respectively. Skill also notes that malformed `--permission_file` JSON returns 400 with no body, so validate with `jq .` first.

**Account-context errors documented as one-liners:**

- **`create ssh-key` under a team-context API key** returns HTTP 400 `team SSH keys are not supported`. Keys must be registered against a personal account.
- **`create-team` / `create team` while already a member** returns `Cannot create a team within a team`. Skill tells the agent to `vastai show members --raw` first.

Each follow-up fix is verified by re-running the same prompts in `TEST_PROMPTS.txt` and `TEST_PROMPTS_2.txt` against the live account. Final commit log:

```
9a25786  fix(skill): note team-context errors for ssh-key + create-team
d3be258  fix(skill): patch 7 issues found in live testing on 2026-06-02
b654dfb  fix(skill): remove vastai execute recommendation — broken upstream
```
