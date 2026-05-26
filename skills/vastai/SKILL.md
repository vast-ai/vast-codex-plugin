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
3. **Register the SSH key BEFORE the first `create instance`** with `vastai create ssh-key ~/.ssh/id_ed25519.pub`. Launching without a registered key produces an unreachable host.
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
9. **Pass `--limit N --latest-first` on `show invoices-v1` and `show instances-v1`.** These commands fire an interactive `Fetch next page? (y/N)` prompt after the first page that blocks `--raw` / non-interactive sessions, even with `--raw` set. `--limit` short-circuits pagination.
10. **Vast.ai does not offer network/shared volumes.** Only local (per-instance) volumes. If the user asks for "shared storage across instances" or "persistent shared state for serverless workers," do NOT reach for `create network-volume` (it's CLI plumbing for an unshipped product and will leave the user with a broken architecture). The correct answer is: replicate data per instance, or use external object storage (S3/GCS/etc.) via `vastai cloud copy`.

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

# 2. Or set the env var (per-shell, overrides stored key)
export VAST_API_KEY=<YOUR_API_KEY>

# Then verify
vastai show user                                    # auth + balance
```

Register your SSH key **before** the first `create instance`:

```bash
vastai create ssh-key ~/.ssh/id_ed25519.pub
```

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

> **vLLM gotcha:** vLLM requires `compute_cap >= 70` (RTX 20-series or newer). Add `compute_cap>=70` to your search filter or you'll get `no kernel image is available` at runtime.

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
vastai label instance <id> --label "training-run-1"      # Tag instance
vastai prepay instance <id> --amount 100                 # Deposit credits into reserved instance
vastai change bid <id> --bid 0.20                        # Change spot bid price
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
- `--onstart-cmd CMD` — Inline startup script (**4048-character hard limit**; the API silently rejects longer payloads and the instance never starts). For anything larger, either use `--onstart FILE`, or gzip+base64 the script and decode inside the command — see "Long onstart scripts" below
- `--entrypoint` / `--args ...` — Override entrypoint and pass args (args must be last)
- `--bid_price PRICE` — Interruptible (spot) pricing in $/hr
- `--template_hash HASH` — Create from template
- `--create-volume <ASK_ID> --volume-size GB --mount-path /root/vol` — Attach new volume
- `--link-volume <VOLUME_ID> --mount-path /root/vol` — Attach existing volume
- `--login '-u USER -p PASS docker.io'` — Private registry credentials

**Long onstart scripts (>4048 chars):**

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
| `intended=running, actual=stopped` | **Spot eviction** — host outbid you | Raise `--bid_price` with `vastai change bid <id> --bid <new>`, then `vastai start instance <id>` |
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
vastai search offers 'gpu_ram>=8 num_gpus=1 compute_cap>=70' -o 'dph_total' --limit 10  # vLLM-compatible
vastai search offers --type bid                          # Interruptible (spot) pricing
vastai search offers --type reserved                     # Reserved pricing
vastai search offers 'verified=any rentable=any gpu_name=H100_SXM'  # Widen specific defaults — see "Hidden defaults" above
vastai search volumes                                    # Volume offers (local only — Vast.ai does not offer network volumes)
vastai search templates "pytorch"                        # Templates
vastai search benchmarks                                 # Benchmark results
vastai search invoices                                   # Invoice history
```

**search offers flags:** `--type on-demand|reserved|bid`, `--order/-o FIELD[-]`, `--limit`, `--storage GB` (storage budget for pricing).

### SSH & file transfer

```bash
vastai ssh-url <id>                                      # ssh:// connection URL (does NOT open a session)
vastai scp-url <id>                                      # scp:// URL
vastai attach ssh <id> "ssh-ed25519 AAAA..."             # Per-instance SSH key attach
vastai detach ssh <id> <ssh_key_id>                      # Per-instance SSH key detach
vastai show ssh-keys                                     # List account SSH keys
vastai create ssh-key ~/.ssh/id_ed25519.pub              # Add key from file (do BEFORE create instance)
vastai create ssh-key                                    # Generate new key if needed
vastai create ssh-key "ssh-ed25519 AAAA..."              # Add SSH key inline
vastai delete ssh-key <id>                               # Remove SSH key from account
vastai update ssh-key <id> "ssh-ed25519 AAAA..."         # Update SSH key value
```

**`ssh-url` does NOT open a session, and its output is NOT directly usable by `ssh`.** Default output is a `host:port` string like `ssh5.vast.ai:38266`; `ssh` rejects that form. Parse the URL into `ssh -p PORT user@host`:

```bash
# Read from --raw JSON (returns ssh://root@host:port)
URL=$(vastai ssh-url --raw <id>)
eval "$(echo "$URL" | awk -F'[/@:]' '{print "ssh -p",$NF,$5"@"$6}')"

# Or pull host/port out of show instance --raw (most reliable)
HOST=$(vastai show instance <id> --raw | jq -r '.ssh_host')
PORT=$(vastai show instance <id> --raw | jq -r '.ssh_port')
ssh -p "$PORT" "root@$HOST"
```

### File copy

```bash
vastai copy local:./data/      <id>:/workspace/data/     # Local → instance (preferred form)
vastai copy <id>:/workspace/   local:./pulled/           # Instance → local
vastai copy <id-a>:/workspace/ <id-b>:/workspace/        # Instance → instance
vastai copy 12345:./data ./local-data                    # Legacy form still works
vastai cancel copy <dst_id>                              # Cancel a running copy

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

### Logs & exec

```bash
vastai logs <id>                                         # Container logs (last 1000 lines)
vastai logs <id> --tail 100                              # Last 100 lines
vastai logs <id> --filter "error"                        # Grep filter
vastai logs <id> --daemon-logs                           # Host daemon logs (instead of container)
vastai execute <id> "nvidia-smi"                         # Run command on instance
vastai execute <id> "ls /workspace" --schedule DAILY     # Scheduled (HOURLY/DAILY/WEEKLY)
```

> Logs are stored in S3 and may take 30–60 s to appear after start. Initial fetches return "waiting on logs" — keep retrying.

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
vastai create workergroup --name "wg-qwen" ...
vastai update workergroup <id> ...
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
vastai search templates "pytorch"
vastai create template --name "Qwen vLLM" --image vastai/vllm:@vastai-automatic-tag \
    --env '-p 8000:8000 -e MODEL_NAME=Qwen/Qwen2.5-3B-Instruct' --disk 40
vastai update template <id> --disk 100
vastai delete template <id>
vastai run benchmarks --template <hash> --gpu-name RTX_4090
```

### Account & API keys

```bash
vastai set api-key <key>                                 # Save API key locally
vastai show api-key <id>                                 # Show a specific key
vastai show api-keys                                     # List all your API keys
vastai create api-key --name "ci" --permissions '{...}'  # Create restricted key
vastai delete api-key <id>
vastai reset api-key                                     # Reset main key (get new from console)
vastai show user                                         # Account info + credit balance
vastai show audit-logs                                   # Account action history
vastai show connections                                  # Cloud storage connections
vastai show ipaddrs                                      # IP address history
vastai transfer credit --recipient EMAIL --amount 10
vastai show subaccounts
vastai create subaccount --email sub@example.com --type child
```

### Environment variables

User-scoped environment variables injected into instances at launch — for API tokens (HuggingFace, OpenAI, etc.) and model config.

```bash
vastai show env-vars --raw                               # List user env vars
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

```bash
vastai show invoices-v1 --limit 50 --latest-first        # Always pass --limit to avoid the (y/N) pagination prompt
vastai show invoices-v1 --charges --limit 50 --latest-first              # Charges only
vastai show invoices-v1 -c --charge-type i v s --limit 50 --latest-first # i=instance v=volume s=serverless
vastai show invoices-v1 --invoices --limit 50 --latest-first             # Invoices only
vastai show invoices-v1 --start-date 2026-01-01 --end-date 2026-02-01 --limit 200
vastai show invoices-v1 -c --format tree --verbose --limit 50 --latest-first  # Full details (tree only)
vastai show invoices-v1 --next-token <TOKEN>             # Resume pagination explicitly
vastai show deposit <id>                                 # Reserved instance deposit info
```

`show invoices` (without `-v1`) is **deprecated** — use `show invoices-v1`.

> **Pagination gotcha:** `show invoices-v1` and `show instances-v1` print *"Fetch next page? (y/N)"* after the first page — even when `--raw` is set. This blocks `claude -p` and other non-interactive sessions. Always pass `--limit N --latest-first` to short-circuit the prompt.

### Teams

```bash
vastai create team --name "myteam"
vastai destroy team
vastai show members
vastai invite member --email user@example.com --role-id <role>
vastai remove member <id>
vastai create team-role --name "viewer" --permissions '{...}'
vastai show team-roles
vastai show team-role <id>
vastai update team-role <id> --permissions '{...}'
vastai remove team-role <id>
```

### 2FA

```bash
vastai tfa status
vastai tfa totp-setup
vastai tfa activate --code 123456
vastai tfa send-sms / send-email / resend-sms / login / regen-codes / auth-new / update / delete
```

> Hosting a machine on Vast? Those commands (`show machines`, `list machine`, `set min-bid`, `schedule maint`, `metrics gpu`, `show earnings`, …) live in the separate `vastai-host` skill.

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` / `Invalid or expired API key` | Invalid key OR scoped key lacks the permission set this command requires | Don't regenerate blindly. Run `vastai show api-keys --raw` to inspect the key's scope; widen permissions or use your primary key. Only `vastai set api-key <new>` if the key itself is wrong. |
| `Your key lacks the machine_read permission group` | Host/admin command (e.g. `metrics gpu`, `show machines`) on a renter account | Use the `vastai-host` skill — these commands are for GPU providers |
| `Insufficient credits` | Account balance too low | Add credits at <https://cloud.vast.ai/billing/> |
| `No offers found` | Filters too restrictive (often blocked by hidden defaults) | Override the specific default (`verified=any`, `rentable=any`) — see "Hidden defaults" in Query syntax. Do NOT pass `-n` to drop all defaults. |
| `Permission denied` (SSH) | No SSH key attached | `vastai create ssh-key` BEFORE `create instance` |
| `Connection refused` | Instance not yet running | Poll `show instance <id>` until `actual_status == "running"` |
| `no kernel image is available` (vLLM) | GPU `compute_cap < 7.0` | Filter `compute_cap>=70` (RTX 20-series+) |
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
