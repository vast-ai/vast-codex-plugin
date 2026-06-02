---
name: vastai
description: Vast.ai CLI for renters — search and launch GPU instances, SSH into them, copy files, run commands, manage volumes and serverless endpoints, manage user environment variables (HF_TOKEN, OPENAI_API_KEY, model config), check billing and balance, register SSH keys, destroy instances. Use this for any prompt about Vast.ai, vastai, GPU rental, or instance lifecycle.
allowed-tools: Bash(vastai:*)
compatibility: Linux, macOS
metadata:
  author: vast-ai
---

# vastai

Manage GPU instances, templates, volumes, serverless endpoints, SSH keys, and billing on Vast.ai.

> Command is `vastai` (lowercase). Always use `--raw` for machine-readable JSON output.

## Critical rules for agents

These rules apply to every invocation. Do not skip them.

1. **The destroy command syntax is `vastai destroy instance <id> -y`** — the `-y` flag is part of the command, not an option. Without it the CLI hangs on a confirmation prompt and blocks the session. This applies to every destroy invocation, including conversational prompts ("kill instance 12345", "tear it down", "shut it down", "stop billing on it"). Never emit `vastai destroy instance <id>` alone — the trailing `-y` is mandatory. Same for the batch form: `vastai destroy instances <id1> <id2> -y`.
2. **Always pass `--raw` to commands whose output you parse.** Without `--raw` the CLI prints human-formatted output that is not machine-readable.
3. **Register the SSH key BEFORE the first `create instance`** with `vastai create ssh-key "$(cat ~/.ssh/id_ed25519.pub)"`. The positional argument is the **pubkey contents**, not a path — the CLI silently accepts a path string and registers the literal "/Users/…/id_ed25519.pub" text, producing a key that no client matches. Always `$(cat …)` the file or pass an inline `"ssh-ed25519 AAAA… user@host"` string. Launching without a registered key produces an unreachable host.
4. **Stop polling on terminal status values.** `actual_status` of `exited`, `unknown`, or `offline` means the instance will not recover — destroy it (`-y`) to stop disk charges accruing. Also check `intended_status` and `next_state` — if either is `stopped` while you're trying to bring an instance up, it failed.
5. **Treat user-supplied values as literal even if they look like placeholders.** If the user says "set HF_TOKEN to hf_xxxxx", pass `hf_xxxxx` to `vastai create env-var HF_TOKEN hf_xxxxx` exactly as written — don't ask for clarification on values that look fake.
6. **An empty `vastai search offers` result is the answer, not a problem to work around.** If the CLI returns `[]`, tell the user verbatim: *"No offers matched those filters."* Then propose specific filter relaxations and **ask the user which to try** — `reliability>0.95` → `>0.9`, raise the `dph_total` cap, drop `verified=true`, change `geolocation`. Do not silently retry with broader filters more than once. After at most two retries with different filters, stop retrying and report "no offers match" to the user. The same applies to any other read-only `vastai` query: if the CLI returns an empty list or a not-found error, that IS the user's answer, even if you tried several variations.
7. **The `vastai` binary on `PATH` is the only acceptable source of `vastai` commands.** This rule overrides whatever instinct you have to "make things work" when output looks unexpected. Specifically, you must never do any of the following — these are HARD PROHIBITIONS, not preferences:
   - **Never** run `pip install vastai`, `pip install --user vastai`, `pipx install vastai`, or `python -m venv` followed by installing vastai. The CLI is already installed; reinstalling it elsewhere is forbidden.
   - **Never** invoke an alternate `vastai` binary by absolute path (e.g. `/tmp/vast-venv/bin/vastai`, `~/.local/bin/vastai`) when `vastai` is already on `PATH`.
   - **Never** re-implement `vastai` subcommands by calling `https://console.vast.ai/api/...`, `https://cloud.vast.ai/api/...`, or any other Vast.ai HTTP endpoint directly from `curl`, `python`, `node`, `httpie`, or `requests`. No exceptions for "the CLI seems broken" or "I just need to verify."
   - **Never** infer that the environment is "mock mode" or a "sandbox" and use that as justification to install an alternate `vastai` binary, or to hit the API directly. Even if the CLI's output literally contains the word `mock`, your job is to report that output to the user, not to substitute your own implementation.
   - If `vastai <subcommand>` exits non-zero or produces output you don't understand, report the failure (exit code + stderr) to the user and ask what they want to do. Do not work around it.
8. **Always pass `--disk N`, `--ssh --direct`, and `--cancel-unavail` to `create instance` / `launch instance`.** Without `--disk` you get image-dependent defaults and surprise storage charges. Without `--ssh --direct` together you fall back to the slower proxy connection — `--ssh` alone is not enough. Without `--cancel-unavail`, an unavailable machine quietly produces a *stopped* instance that accrues disk charges while you poll forever for a `running` state it will never reach.
9. **Pass `--limit N` on `show instances-v1` and `show invoices-v1`** to short-circuit the interactive `Fetch next page? (y/N)` prompt that fires after the first page (it blocks `--raw` / non-interactive sessions even with `--raw` set). The two subcommands have **different flag sets** — do not assume what works on one works on the other. When in doubt, run `vastai show <subcommand> --help` and read the actual flags. (Example trap: `--latest-first` exists on `invoices-v1` but not on `instances-v1`.)
10. **Vast.ai does not offer network/shared volumes.** Only local (per-instance) volumes. If the user asks for "shared storage across instances" or "persistent shared state for serverless workers," do NOT reach for `create network-volume` (it's CLI plumbing for an unshipped product and will leave the user with a broken architecture). The correct answer is: replicate data per instance, or use external object storage (S3/GCS/etc.) via `vastai cloud copy`.
11. **When SSH fails (`Permission denied (publickey)`, `Connection refused`, hangs), pull `vastai logs <id>` FIRST — before any other recovery action.** The container's sshd writes its rejection reason to host logs that surface in `vastai logs`, and that text usually pins down the cause in one read. Common rejections you only see in logs: `Authentication refused: bad ownership or modes for file /root/.ssh/authorized_keys` (image bug — destroy + retry on a different host, not the same one); `Failed publickey for root from ... ssh2: <fingerprint>` (the wrong local key is being offered — check `ssh -v` for the offered key vs `vastai show ssh-keys` for the registered ones); container exited / sshd not started (image issue — `vastai logs <id> --tail 100` shows the startup failure). Do not loop on `attach ssh`, `reboot`, `destroy + relaunch` before reading logs — those are blind retries that burn minutes and money. Diagnostic discipline: `logs` then act, never act then guess.

## Install

```bash
# PyPI (recommended)
pip install vastai
```

## Setup / first-time auth

Create an API key at **<https://console.vast.ai/manage-keys/>** (not `cloud.vast.ai/account` — that URL does not exist).

Two ways to authenticate, in order of preference:

```bash
# 1. Persist (stored at ~/.config/vastai/vast_api_key)
vastai set api-key <YOUR_API_KEY>

# 2. Or set the env var (per-shell)
export VAST_API_KEY=<YOUR_API_KEY>

# Then verify
vastai show user                                    # auth + balance
```

> **Precedence and the admin-key shadowing trap.** Resolution order is: `--api-key <key>` on the command > `$VAST_API_KEY` env var > stored key at `~/.config/vastai/vast_api_key`. A `VAST_API_KEY` set in the shell **silently overrides** whatever the user just stored with `vastai set api-key`. The CLI prints a one-line `⚠️ VAST_API_KEY is set in your environment and overrides the key you just saved` after `set api-key`, but it is easy to miss.
>
> If the user intended their stored key to be the active one (e.g. they deliberately created a narrower-scope key), check `env | grep VAST_API_KEY` before running authenticated commands. If `$VAST_API_KEY` is set and contains a broader-scope key, prompt the user to `unset VAST_API_KEY` so subsequent commands use the scoped stored key.

Register your SSH key **before** the first `create instance`. The positional argument is the pubkey **contents**, not a path:

```bash
vastai create ssh-key "$(cat ~/.ssh/id_ed25519.pub)"
```

Passing the path directly (`vastai create ssh-key ~/.ssh/id_ed25519.pub`) silently registers the literal string "/path/to/file" — no error, but no client key will ever match it.

**If the account has 2FA enabled,** authenticate once per shell with `vastai tfa login` — the CLI writes a session key to `~/.config/vastai/vast_tfa_key` and uses it transparently on subsequent calls:

```bash
# Recommend the user run this themselves with `!` prefix so the 6-digit code stays out of the transcript:
!vastai tfa login --method-type totp --code 123456
```

Without an active TFA session, **almost every authenticated read** (`show user`, `show ssh-keys`, `show instances-v1`, `show env-vars`, `show invoices-v1`, etc.) returns a `401` whose body contains *"requires you to have logged in using Two Factor Authentication."* Search (`vastai search offers`) and a few other read-only public endpoints still work. See the "Common errors" table for the exact remediation pattern.

## Quick start

```bash
vastai search offers 'gpu_name=RTX_4090 num_gpus=1 verified=true direct_port_count>=1 rentable=true' -o 'dlperf_usd-'
vastai create instance <OFFER_ID> \
    --image vastai/pytorch:@vastai-automatic-tag \
    --disk 20 --ssh --direct --cancel-unavail
# Response: {"success": true, "new_contract": <INSTANCE_ID>}
vastai show instance <INSTANCE_ID>                  # Poll until actual_status == "running"
vastai ssh-url <INSTANCE_ID>                        # Get SSH connection string (parse, don't $() — see SSH section)
vastai copy local:./data/ <INSTANCE_ID>:/workspace/ # Upload files
vastai destroy instance <INSTANCE_ID> -y            # Clean up (stops all billing)
```

- `@vastai-automatic-tag` is server-resolved per machine. It only works on **Vast curated images** (`vastai/pytorch`, `vastai/vllm`, `vastai/comfy`, `vastai/base-image`, `vastai/linux-desktop`). Third-party images like `pytorch/pytorch` need a real tag (e.g. `pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime`).

## Global flags

Available on every command:

```
--api-key KEY    Override stored API key
--raw            Output machine-readable JSON (agents should always use this)
--full           Print full results (don't page with less)
--explain        Show underlying API calls (useful for debugging)
--curl           Show equivalent curl command
--no-color       Disable colored output
--url URL        Override server REST API URL
--retry RETRY    Set retry limit for API calls
--version        Show CLI version
```

## Query syntax

Search commands accept filter expressions. Operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `in`, `notin`.

```bash
'gpu_name=RTX_4090 num_gpus=1'           # Exact match + numeric
'gpu_ram>=48 reliability>0.95'           # Greater-than filters
'geolocation=EU dph_total<=2.0'          # Region + price cap
'gpu_name in ["RTX 4090","RTX 3090"] geolocation notin [CN,VN]'
```

Quote the whole expression — `>` and `<` are shell metacharacters. String values can use underscores (`gpu_name=RTX_4090`) or quoted spaces (`gpu_name='RTX 4090'`).

**Common filter fields:** `num_gpus`, `gpu_name`, `gpu_ram`, `cpu_ram`, `disk_space`, `reliability`, `compute_cap`, `cuda_vers`, `inet_up`, `inet_down`, `dph_total`, `geolocation`, `direct_port_count`, `static_ip`, `verified`, `rentable`, `dlperf`, `dlperf_usd`, `total_flops`, `cpu_arch`, `gpu_arch`.

**Common sort fields (`-o`):**
- `dlperf_usd-` — best DL-perf per dollar (recommended default for value)
- `dph_total` — cheapest first
- `score-` — overall value metric (CLI default)
- `dph_base` is the **legacy** field — prefer `dph_total`.

**Sort direction:** plain field name is ascending; postfix `-` for descending (`-o 'dph_total-'`).

**Hidden defaults on `search offers`:** Even with no `-n` flag, the CLI applies these implicit filters:

```
verified=true   external=false   rentable=true   rented=false   disk_space>=8
```

Roughly 90% of marketplace listings are hidden by these. To widen, **override the specific filter** (e.g. `verified=any` for unverified offers, `rentable=any` to include already-rented machines). **Do not pass `-n` / `--no-default`** to drop all four at once — that exposes the renter to unverified, external, or already-rented offers and produces unpredictable launches.

## Recommended Vast images

Vast curated images plus `@vastai-automatic-tag`:

```
vastai/base-image:@vastai-automatic-tag          # Minimal Ubuntu base
vastai/pytorch:@vastai-automatic-tag             # PyTorch + CUDA
vastai/vllm:@vastai-automatic-tag                # vLLM (model via env)
vastai/comfy:@vastai-automatic-tag               # ComfyUI (checkpoint via env)
vastai/linux-desktop:@vastai-automatic-tag       # Linux desktop (VNC/RDP)
```

For vLLM/Comfy, set the model via `--env`, not `--args`:

```bash
# vLLM
vastai create instance <OFFER_ID> --image vastai/vllm:@vastai-automatic-tag --disk 40 --ssh --direct \
  --env '-e MODEL_NAME=Qwen/Qwen2.5-3B-Instruct -e HF_TOKEN=hf_xxx'

# ComfyUI
vastai create instance <OFFER_ID> --image vastai/comfy:@vastai-automatic-tag --disk 40 --ssh --direct \
  --env '-e CHECKPOINT_MODEL=black-forest-labs/FLUX.1-schnell -e HF_TOKEN=hf_xxx'
```

Browse pre-configured models at <https://vast.ai/model-library>.

> **vLLM gotcha:** vLLM requires a minimum CUDA compute capability. Vast's `compute_cap` field is **not** the raw `X.Y` decimal — it's an integer encoding. Read the current encoding from `vastai search offers --help` (the field's description line shows examples), pick the threshold for your target compute capability, and filter with that exact integer. If you guess based on the decimal version, the filter will silently let unsupported GPUs through and vLLM will fail at runtime with `no kernel image is available`.

## Commands

### Instances

```bash
vastai show instances                                    # Legacy list
vastai show instances-v1                                 # Paginated, filterable (recommended)
vastai show instances-v1 --status running loading        # Filter by status
vastai show instances-v1 --gpu-name 'RTX 4090'           # Filter by GPU
vastai show instances-v1 --label training                # Filter by label
vastai show instances-v1 --order-by start_date desc      # Sort
vastai show instances-v1 --cols id,status,gpu,dph        # Custom columns
vastai show instances-v1 -a                              # Auto-fetch all pages
vastai show instance <id>                                # Poll single instance

vastai create instance <offer-id> --image vastai/pytorch:@vastai-automatic-tag --disk 20 --ssh --direct --cancel-unavail
# Response includes "new_contract": <id> — that is your instance ID

vastai launch instance -g RTX_4090 -n 1 -i vastai/pytorch:@vastai-automatic-tag -d 32 --ssh --direct --cancel-unavail
# Search + create top result in one call. Short flags: -g gpu-name, -n num-gpus, -i image, -d disk, -r region.

vastai start instance <id>                               # Start stopped instance
vastai stop instance <id>                                # Stop (preserves disk, no GPU charges)
vastai reboot instance <id>                              # Stop + start
vastai recycle instance <id>                             # Destroy + recreate container — re-pulls image, keeps GPU priority
vastai update instance <id> --image NEW_IMAGE            # In-place update of template/image/args/env/onstart
vastai destroy instance <id> -y                          # Permanent delete (-y required for non-interactive)
vastai destroy instances <id1> <id2> -y                  # Batch delete
vastai label instance <id> "training-run-1"              # Tag instance (label is POSITIONAL, not --label)
vastai prepay instance <id> 100                          # Deposit credits — amount POSITIONAL, not --amount
vastai change bid <id> --price 0.20                      # Change spot bid price (--price, NOT --bid / --bid_price)
vastai accept price-increase <id>                        # Accept pending host price hike
```

**`recycle` vs `update`:** Use `recycle` to re-pull the image without losing GPU priority (e.g. after a `docker push`). Use `update --image NEW` to swap to a different image in place.

**create instance flags:**
- `--image IMAGE` — Docker image
- `--disk DISK` — Local disk in GB (**always pass this**)
- `--ssh` / `--jupyter` — Connection type
- `--direct` — Faster direct connections (use with `--ssh`)
- `--cancel-unavail` — **Always pass this.** Fail if the chosen machine is unavailable instead of silently creating a stopped instance that bills for disk
- `--label LABEL` — Instance label
- `--env ENV` — Env vars and port mappings, e.g. `'-e TZ=UTC -p 8080:8080'`
- `--onstart FILE` — Path to a startup script file
- `--onstart-cmd CMD` — Inline startup script. The server enforces a length cap on `args`; payloads above the cap are rejected at `create instance` with `error 400/3471: Invalid args: len(args) > N` (`N` is whatever the server is currently configured to). If you hit it, **read the error for the current limit**, then either pass `--onstart FILE` (uploads the file, sidesteps the arg cap entirely) or gzip+base64 the script and decode inline — see "Long onstart scripts" below
- `--entrypoint` / `--args ...` — Override entrypoint and pass args (args must be last)
- `--bid_price PRICE` — Interruptible (spot) pricing in $/hr
- `--template_hash HASH` — Create from template
- `--create-volume <ASK_ID> --volume-size GB --mount-path /root/vol` — Attach new volume
- `--link-volume <VOLUME_ID> --mount-path /root/vol` — Attach existing volume
- `--login '-u USER -p PASS docker.io'` — Private registry credentials

**Long onstart scripts (anything risking the server's arg-length cap — see `--onstart-cmd` note above):**

```bash
SCRIPT_B64=$(gzip -c ./long_script.sh | base64 -w0)
vastai create instance <OFFER_ID> \
    --image vastai/pytorch:@vastai-automatic-tag --disk 20 --ssh --direct --cancel-unavail \
    --onstart-cmd "echo $SCRIPT_B64 | base64 -d | gunzip | bash"
```

Or just use `--onstart ./long_script.sh` which uploads the file directly.

**Instance status fields (read all four):**

`show instance --raw` returns four status fields. Don't act on `actual_status` alone — diagnose with all four.

| Field | What it tells you |
|-------|-------------------|
| `intended_status` | What the user/system asked for (`running`, `stopped`). The target. |
| `actual_status` | Current observed state — the polling target. See values table below. |
| `cur_state` | Provisioning sub-state (e.g. `scheduling`, `loading`, `running`). Distinguishes "still spinning up" from "stuck." |
| `next_state` | Scheduled transition queued by host or system (e.g. maintenance window about to evict). |

**`actual_status` values:**

| Value | Meaning |
|-------|---------|
| `null` | Provisioning |
| `created` | Created, not yet provisioned |
| `loading` | Image downloading / container starting |
| `running` | Active — GPU charges apply |
| `stopped` | Halted — disk charges only |
| `frozen` | Paused with memory — GPU charges apply |
| `exited` | Container process exited unexpectedly |
| `rebooting` | Restarting (transient) |
| `unknown` | No recent heartbeat from host |
| `offline` | Host disconnected from Vast servers |

**Common combinations:**

| Pattern | Meaning | Action |
|---------|---------|--------|
| `intended=running, actual=stopped` | **Spot eviction** — host outbid you | Raise the bid with `vastai change bid <id> --price <new>`, then `vastai start instance <id>`. (`change bid` uses `--price`, not `--bid` — different from the `--bid_price` flag on `create instance`.) |
| `actual=created, cur_state=scheduling` | Still provisioning | Keep polling |
| `actual=loading` (long) | Image pulling (vLLM ~15 GB takes 5–10 min) | Keep polling; tail `vastai logs <id>` |
| `actual=running, intended=stopped` | Stop is queued | Transient; will become `stopped` |
| `actual=stopped, intended=stopped` | Cleanly stopped by user | `vastai start instance <id>` to resume |
| `actual in [exited, unknown, offline]` | **Terminal failure** | Destroy with `-y` and retry on a different offer |
| `next_state=stopped` while bringing up | Host has queued an eviction | Treat as fatal; try another offer |

> **Poll loop warning:** Terminal `actual_status` values (`exited`, `unknown`, `offline`) never recover. Always add a timeout — your script otherwise loops forever while disk charges accrue.

> **Charges:** Storage charges begin at creation (or earlier if `--cancel-unavail` is omitted on an unavailable machine). GPU charges begin when status reaches `running`.

### Polling pattern (with timeout)

```bash
INST=<id>
deadline=$((SECONDS + 600))
while [ $SECONDS -lt $deadline ]; do
  STATUS=$(vastai show instance $INST --raw | jq -r '.actual_status // "null"')
  case "$STATUS" in
    running)               echo "ready"; break ;;
    exited|unknown|offline) echo "fatal: $STATUS"; vastai destroy instance $INST -y; exit 1 ;;
    *)                     echo "status=$STATUS"; sleep 10 ;;
  esac
done
[ $SECONDS -ge $deadline ] && { echo "timed out"; vastai destroy instance $INST -y; exit 1; }
```

### Container port ≠ host port

`-p 8000:8000` in `--env` is NOT the host port — Vast remaps to a random host port. Always read the actual mapping:

```bash
IP=$(vastai show instance <id> --raw | jq -r '.public_ipaddr')
PORT=$(vastai show instance <id> --raw | jq -r '.ports."8000/tcp"[0].HostPort')
echo "http://$IP:$PORT"
```

### Search

```bash
vastai search offers                                     # Default: verified, on-demand, score-sorted
vastai search offers 'gpu_name=RTX_4090 num_gpus=1 verified=true direct_port_count>=1' -o 'dlperf_usd-'
vastai search offers 'num_gpus>=4 reliability>0.99' -o 'num_gpus-'
vastai search offers 'gpu_ram>=8 num_gpus=1 compute_cap>=<THRESHOLD>' -o 'dph_total' --limit 10  # Derive <THRESHOLD> from `vastai search offers --help` (compute_cap encoding) for your target CUDA capability — see the vLLM gotcha above
vastai search offers --type bid                          # Interruptible (spot) pricing
vastai search offers --type reserved                     # Reserved pricing
vastai search offers 'verified=any rentable=any gpu_name=H100_SXM'  # Widen specific defaults — see "Hidden defaults" above
vastai search volumes                                    # Volume offers (local only — Vast.ai does not offer network volumes)
vastai search templates 'name=pytorch'                   # Templates (structured query — NOT free-text. Fields: name, creator_id, count_created, hash_id, image, tag, recommended, use_ssh, jup_direct, ssh_direct, …)
vastai search templates 'count_created>100 recommended=true'
vastai search benchmarks                                 # Benchmark results
vastai search invoices 'amount_cents>3000'               # Invoice history (structured query, same syntax)
```

**search offers flags:** `--type on-demand|reserved|bid`, `--order/-o FIELD[-]`, `--limit`, `--storage GB` (storage budget for pricing).

### SSH & file transfer

```bash
vastai ssh-url <id>                                      # ssh:// connection URL (does NOT open a session)
vastai scp-url <id>                                      # scp:// URL
vastai attach ssh <id> "ssh-ed25519 AAAA..."             # Per-instance SSH key attach
vastai detach ssh <id> <ssh_key_id>                      # Per-instance SSH key detach. Note: `vastai detach ssh --help` prints `vastai detach <id> <key_id>` (no `ssh`) — the help text is misleading; the actual subcommand IS `detach ssh`. Pass numeric IDs only; passing the public-key string crashes server-side.
vastai show ssh-keys                                     # List account SSH keys
vastai create ssh-key "$(cat ~/.ssh/id_ed25519.pub)"     # Add key — positional takes CONTENTS, not a path. Bare path strings are silently accepted and stored verbatim.
vastai create ssh-key                                    # Generate new key if needed
vastai create ssh-key "ssh-ed25519 AAAA..."              # Add SSH key inline
vastai delete ssh-key <id>                               # Remove SSH key from account
vastai update ssh-key <id> "ssh-ed25519 AAAA..."         # Update SSH key value
```

**`ssh-url` does NOT open a session, and its output is NOT directly usable by `ssh`.** Both with and without `--raw` it returns the **same plain string** in the form `ssh://root@<host>:<port>` (e.g. `ssh://root@ssh5.vast.ai:38266`). The `--raw` flag is accepted but does NOT yield JSON — `ssh-url` has no structured output. `ssh` rejects the `ssh://...` form directly. Parse it, or — the most reliable path — read `ssh_host` and `ssh_port` from `show instance --raw` (which IS real JSON):

```bash
# Preferred — JSON from show instance is reliable structured output
HOST=$(vastai show instance <id> --raw | jq -r '.ssh_host')
PORT=$(vastai show instance <id> --raw | jq -r '.ssh_port')
ssh -p "$PORT" "root@$HOST"

# Fallback — parse the plain ssh:// string from ssh-url --raw
URL=$(vastai ssh-url --raw <id>)             # returns: ssh://root@ssh5.vast.ai:38266 (a string)
HOST=$(echo "$URL" | awk -F'[@:/]' '{print $5}')
PORT=$(echo "$URL" | awk -F'[@:/]' '{print $NF}')
ssh -p "$PORT" "root@$HOST"
```

### File copy

```bash
vastai copy local:./data/      <id>:/workspace/data/     # Local → instance (preferred form)
vastai copy <id>:/workspace/   local:./pulled/           # Instance → local
vastai copy <id-a>:/workspace/ <id-b>:/workspace/        # Instance → instance
vastai copy 12345:./data ./local-data                    # Legacy form still works
vastai cancel copy <dst>                                 # Cancel a running copy. <dst> can be a bare instance id (`12371`) or the full `instance_id:/path` form to disambiguate multiple copies into the same instance.

# Cloud storage sync — needs a configured connection (set up in console at https://cloud.vast.ai/cloud-integrations/)
vastai show connections
vastai cloud copy --src ./data --dst s3://bucket/path \
    --instance 12345 --connection <conn-id> \
    --transfer "Instance To Cloud"

# Recurring sync
vastai cloud copy --src ./logs --dst s3://bucket/logs/ \
    --instance 12345 --connection 7 --transfer "Instance To Cloud" \
    --schedule DAILY --hour 4
```

### Logs

```bash
vastai logs <id>                                         # Container logs (last 1000 lines)
vastai logs <id> --tail 100                              # Last 100 lines
vastai logs <id> --filter "error"                        # Grep filter
vastai logs <id> --daemon-logs                           # Host daemon logs (instead of container)
```

> Logs are stored in S3 and may take 30–60 s to appear after start. Initial fetches return "waiting on logs" — keep retrying.
>
> **There is NO working way to inspect or run commands on a STOPPED instance.** Verified 2026-06-02: `vastai execute` crashes (`AttributeError: 'str' object has no attribute 'get'`) on valid input, and `vastai copy <id>:/path ./local` against a stopped instance fails with `rsync: Unknown module '<id>'` because the in-instance rsync daemon isn't running. To inspect a stopped instance, `vastai start instance <id>`, wait for `actual_status == running`, then SSH in or `vastai copy`. Don't suggest `execute` — it appears in `vastai --help` but doesn't work.
>
> For arbitrary commands on a **running** instance: SSH in. Read `ssh_host` / `ssh_port` from `show instance --raw` and `ssh -p $PORT root@$HOST '<command>'`.

### Volumes

Vast.ai offers **local (per-instance) volumes only**. There is no network/shared-volume product — see rule 10. If the user asks for shared storage across instances, recommend per-instance replication or external object storage via `vastai cloud copy`.

```bash
# Local volumes (per-machine)
vastai search volumes
vastai show volumes
vastai create volume <offer_id> -s 500 -n my-data        # Size in GB, name optional
vastai clone volume <source_id> <dest_id> -s 500
vastai delete volume <id>

# Container snapshots
vastai take snapshot <instance_id> \
    --repo myorg/myimage --container_registry docker.io \
    --docker_login_user $DOCKER_USER --docker_login_pass $DOCKER_TOKEN \
    --pause true                                         # Pause during commit (safer, slower)
```

### Serverless & deployments

3-tier model: **endpoints** route requests to **worker groups** which back **deployments**.

```bash
vastai show endpoints
vastai create endpoint --endpoint_name "qwen25-3b" \
    --min_load 10 --target_util 0.9 --cold_mult 2.5 \
    --cold_workers 1 --max_workers 20 \
    --max_queue_time 30 --target_queue_time 10 --inactivity_timeout 600
vastai update endpoint <id> --max_workers 50
vastai delete endpoint <id>
vastai get endpt-logs <id>

vastai show workergroups
vastai create workergroup --template_hash <HASH> --endpoint_name "qwen25-3b" --cold_workers 1   # No --name flag — identity is template + endpoint. Use --template_hash (or --template_id) + --endpoint_name (or --endpoint_id). Pass --search_params if not inheriting from template. Requires an admin-scope API key — scoped/read-only keys return HTTP 403.
vastai update workergroup <id> --endpoint_id <endpoint_id> [options]    # --endpoint_id is REQUIRED per the usage line (vastai update workergroup --help)
vastai update workers <id>                               # Trigger rolling worker update
vastai update workers <id> --cancel                      # Cancel an in-progress rollout
vastai delete workergroup <id>
vastai get wrkgrp-logs <id>
vastai get endpt-workers <id>                            # List workers with status + measured_perf

vastai show deployments
vastai show deployment <id>
vastai show deployment-versions <id>
vastai delete deployment <id>

vastai show scheduled-jobs
vastai delete scheduled-job <id>
```

### Templates

```bash
vastai search templates 'name=pytorch'    # Structured query — fields: name, creator_id, count_created, hash_id, image, tag, recommended, use_ssh, jup_direct, ssh_direct, recent_create_date, recommended_disk_space
vastai create template --name "Qwen vLLM" --image vastai/vllm:@vastai-automatic-tag \
    --env '-p 8000:8000 -e MODEL_NAME=Qwen/Qwen2.5-3B-Instruct' --disk_space 40       # --disk_space, NOT --disk
vastai update template <HASH_ID> --disk_space 100                                      # POSITIONAL is the template hash_id (string), not a numeric id. Flag is --disk_space.
vastai delete template --template-id <id>                                              # OR: --hash-id <hash>. NO POSITIONAL — must use one of the two flags.
vastai run benchmarks --template_hash <hash> --gpus RTX_4090                           # --template_hash (NOT --template); --gpus (plural, comma-separated, NOT --gpu-name). Add --num_gpus N for multi-GPU benches. If you also pass --endpoint_name, it must be `[a-z0-9_-]+` only — `.`, `/`, spaces, etc. fail with API 400 "Value error, contains disallowed shell characters".
```

### Account & API keys

```bash
vastai set api-key <key>                                 # Save API key locally
vastai show api-key <id>                                 # Show a specific key
vastai show api-keys                                     # List all your API keys
vastai create api-key --name "ci" --permission_file ./perms.json   # Create restricted key. --permission_file takes a FILE PATH to valid JSON (NOT inline JSON). Malformed/empty JSON returns HTTP 400 with no body — validate the file with `jq . perms.json` first. Requires an admin-scope key. See https://vast.ai/docs/cli/roles-and-permissions
vastai delete api-key <id>
vastai reset api-key                                     # Reset main key (get new from console)
vastai show user                                         # Account info + credit balance
vastai show audit-logs                                   # Account action history
vastai show connections                                  # Cloud storage connections
vastai show ipaddrs                                      # IP address history
vastai transfer credit --recipient EMAIL --amount 10
vastai show subaccounts
vastai create subaccount --email sub@example.com --username sub --password '<pw>' --type host    # --type is `host` or `client`. All four flags are required.
```

### Environment variables

User-scoped environment variables injected into instances at launch — for API tokens (HuggingFace, OpenAI, etc.) and model config.

```bash
vastai show env-vars --raw                               # List names only (values are masked as '*****')
vastai show env-vars -s --raw                            # Include values (-s / --show-values is required to reveal them)
vastai create env-var HF_TOKEN hf_abc123 --raw           # Create (value passed literally)
vastai update env-var HF_TOKEN hf_new456 --raw
vastai delete env-var HF_TOKEN --raw
```

> **Account env-vars vs `--env`:** Account env-vars are stored server-side and auto-injected into *every* instance you create. `--env` on `create instance` is per-instance only and doesn't persist. Use account env-vars for secrets you reuse (HF_TOKEN, OPENAI_API_KEY) and `--env` for per-launch config (port mappings, MODEL_NAME, TZ).

Common prompts and the calls they map to:

- *"set HF_TOKEN to hf_xxxxx"* → `vastai create env-var HF_TOKEN hf_xxxxx --raw`
- *"add a HuggingFace token"* → ask for the token value, then `vastai create env-var HF_TOKEN <value> --raw`
- *"list my env vars"* → `vastai show env-vars --raw`
- *"unset OPENAI_API_KEY"* → `vastai delete env-var OPENAI_API_KEY --raw`

### Billing

**One of `-c` / `--charges` or `-i` / `--invoices` is REQUIRED.** Bare `vastai show invoices-v1 --raw --limit <N> --latest-first` (without either) fails — the server needs to know which ledger to return. Always pass `--limit` too to avoid the `(y/N)` pagination prompt (cap is in `--help`).

```bash
vastai show invoices-v1 -c --limit <N> --latest-first                     # Charges (most common)
vastai show invoices-v1 -i --limit <N> --latest-first                     # Paid invoices
vastai show invoices-v1 -c --charge-type i v s --limit <N> --latest-first # i=instance v=volume s=serverless
vastai show invoices-v1 -c --start-date <YYYY-MM-DD> --end-date <YYYY-MM-DD> --limit <N>
vastai show invoices-v1 -c --format tree --verbose --limit <N> --latest-first  # Full details (tree only)
vastai show invoices-v1 -c --next-token <TOKEN>          # Resume pagination explicitly
vastai show deposit <id>                                 # Reserved instance deposit info
```

`show invoices` (without `-v1`) is **deprecated** — use `show invoices-v1`.

> **Pagination gotcha:** `show invoices-v1` and `show instances-v1` print *"Fetch next page? (y/N)"* after the first page — even when `--raw` is set. This blocks `claude -p` and other non-interactive sessions. Always pass `--limit N` to short-circuit the prompt. The two commands have **separate flag sets** — check each with `vastai show <subcommand> --help` rather than assuming flags carry over (notably, `--latest-first` is invoices-v1 only).

### Teams

**Subcommand-name version skew on team creation.** Newer CLIs expose `vastai create-team` (hyphenated, with `--team-name`); older CLIs expose `vastai create team` (with a space, taking `--team-name` or just a positional name). Before running, check which form your CLI parses: `vastai --help 2>&1 | grep -E 'create[ -]team'`. The skill below shows the hyphenated form; if the parser rejects it, drop the hyphen and retry. Either way, the flag is `--team-name`, not `--name`.

```bash
vastai create-team --team-name "myteam"                  # Hyphenated subcommand on newer CLIs. If parser rejects, try `vastai create team --team-name "myteam"`.
vastai create-team --team-name "myteam" --transfer-credit 50  # Optionally seed from personal credit
vastai destroy team
vastai show members
vastai show team-roles                                   # ALWAYS run this first when inviting — roles are TEAM-DEFINED, not a fixed enum. "billing-admin", "viewer" etc. are NOT preset; using an unknown role name triggers a generic HTTP 500.
vastai invite member --email user@example.com --role <role-name>     # --role, NOT --role-id. <role-name> must come from `show team-roles`.
vastai remove member <id>
vastai create team-role --name "viewer" --permissions ./role.json    # --permissions takes a FILE PATH to JSON, NOT inline
vastai show team-role <id>
vastai update team-role <id> --permissions ./role.json               # Same — file path
vastai remove team-role <id>
```

### 2FA

```bash
# Setup
vastai tfa status                                                         # List configured 2FA methods + IDs
vastai tfa totp-setup                                                     # Start TOTP enrollment (returns secret to scan)
vastai tfa activate CODE --secret SECRET -t {sms,totp}                    # Finish enrollment. CODE is positional.
vastai tfa send-sms                                                       # Send an SMS code to the registered phone
vastai tfa send-email                                                     # Send an email code
vastai tfa resend-sms --secret SECRET [--phone-number +1XXX]              # Re-send during a login flow

# Login / auth flows
vastai tfa login --code CODE [-t {sms,totp,email}] [--secret SECRET] [--backup-code CODE] [--method-id ID]
vastai tfa auth-new --code CODE --secret SECRET                           # Authenticate a new device session
vastai tfa regen-codes --code CODE [-t METHOD] [--secret SECRET]          # Regenerate one-time backup codes

# Manage methods
vastai tfa update METHOD_ID [--label NAME] [--set-primary true]
vastai tfa delete --id-to-delete METHOD_ID --code CODE [-t METHOD]        # Remove a 2FA method
```
> `--method-type` (`-t`) accepts `sms`, `totp`, or `email` (some subcommands only support a subset — check `--help`). `--backup-code` is accepted as an alternative to `--code` on `login`, `delete`, `regen-codes`, `auth-new`.

> Hosting a machine on Vast? Those commands (`show machines`, `list machine`, `set min-bid`, `schedule maint`, `metrics gpu`, `show earnings`, …) live in the separate `vastai-host` skill.

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `401` + `"...requires you to have logged in using Two Factor Authentication"` in body | Account has 2FA enabled but no current TFA session key — affects almost all authenticated reads (`show user`, `show ssh-keys`, `show instances-v1`, `show invoices-v1`, `show env-vars`, etc.) | Run `vastai tfa login --method-type {totp,sms,email} --code <CODE>` once per shell. The CLI writes a session key to `~/.config/vastai/vast_tfa_key` and prefers it transparently on subsequent calls. **Tell the user to prefix the command with `!` in the Claude transcript so the 6-digit code does not enter conversation history.** Do NOT ask the user for a new API key — that won't fix it. |
| `401 Unauthorized` / `Invalid or expired API key` (no 2FA wording) | Invalid key OR scoped key lacks the permission set this command requires | Don't regenerate blindly. First check `env | grep VAST_API_KEY` — a shell env var may be shadowing the stored key. Then run `vastai show api-keys --raw` to inspect the key's scope; widen permissions or use your primary key. Only `vastai set api-key <new>` if the key itself is wrong. |
| `Your key lacks the machine_read permission group` | Host/admin command (e.g. `metrics gpu`, `show machines`) on a renter account | Use the `vastai-host` skill — these commands are for GPU providers |
| `Insufficient credits` | Account balance too low | Add credits at <https://cloud.vast.ai/billing/> |
| `No offers found` | Filters too restrictive (often blocked by hidden defaults) | Override the specific default (`verified=any`, `rentable=any`) — see "Hidden defaults" in Query syntax. Do NOT pass `-n` to drop all defaults. |
| `Permission denied` (SSH) | No SSH key attached | `vastai create ssh-key` BEFORE `create instance` |
| `Connection refused` | Instance not yet running | Poll `show instance <id>` until `actual_status == "running"` |
| `no kernel image is available` (vLLM or similar) | The launched GPU's CUDA compute capability is below what the workload requires | Filter `compute_cap` in the search query. `compute_cap` is an encoded integer, not the decimal version — read its description in `vastai search offers --help` to pick the right threshold. |
| Hangs on `destroy instance` | Confirmation prompt | Add `-y`: `vastai destroy instance <id> -y` |
| Wrong host port | Reading `-p 8000:8000` literally | Read `.ports."8000/tcp"[0].HostPort` from `show instance --raw` |

## Troubleshooting

### Instance failed silently
Don't trust `actual_status` alone — check `intended_status` and `next_state`. If either is `stopped` while bringing an instance up, it failed.

```bash
vastai show instance <id> --raw | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k in ('actual_status', 'intended_status', 'next_state', 'status_msg'):
    print(f'{k}: {d.get(k)}')
"
```

Common causes: GPU hardware error (try different offer), missing/private image, insufficient disk, CUDA incompat.

### Long startup
Large images (vLLM ~15 GB) can take 5–10 min to pull. Status shows `loading` while pulling, `running` when up. Tail with `vastai logs <id> --tail 50`.

## URLs

```
https://console.vast.ai/instances/         Your instances
https://console.vast.ai/create/            Search GPU offers
https://console.vast.ai/manage-keys/       Create and manage API keys
https://cloud.vast.ai/billing/             Billing
https://cloud.vast.ai/cloud-integrations/  Cloud storage connections
https://vast.ai/model-library              Pre-configured models
https://docs.vast.ai/llms.txt              Full docs index for LLMs
```

## Environment variables

- `VAST_API_KEY` — API key (alternative to `vastai set api-key`)
- `VAST_URL` — API endpoint override (default `https://console.vast.ai`)
