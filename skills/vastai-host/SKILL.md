---
name: vastai-host
description: Vast.ai CLI for GPU hosts/providers — list and unlist machines on the marketplace, set pricing (min-bid, default GPU price), configure default jobs, schedule maintenance windows, run self-tests, view earnings, monitor marketplace metrics (gpu, gpu-trends, gpu-locations), manage network disks and clusters, defrag machines, clean up expired storage. Use this for any prompt about hosting on Vast, listing a machine, machine pricing, maintenance windows, host earnings, marketplace metrics, or any vastai command for GPU providers.
allowed-tools: Bash(vastai:*)
compatibility: Linux, macOS
metadata:
  author: vast-ai
---

# vastai-host

Manage machines you host on the Vast.ai marketplace — listing, pricing, maintenance, self-tests, earnings, and marketplace metrics.

> Command is `vastai` (lowercase). Always use `--raw` for machine-readable JSON output.
> Renting instances (not hosting)? Use the `vastai` skill instead.

## Critical rules for agents

These rules apply to every invocation. Do not skip them.

1. **Always pass `--raw` to commands whose output you parse.** Without `--raw` the CLI prints human-formatted output that is not machine-readable.
2. **Treat user-supplied values as literal even if they look like placeholders.** If the user says "set min-bid on machine 12345 to 0.10", pass `0.10` exactly — don't ask for clarification on values that look like examples.
3. **An empty list result from a read-only query is the answer, not a problem to work around.** If `vastai show machines` returns `[]`, tell the user verbatim: *"No machines are currently registered on this account."* Do not silently retry, do not invent IDs, do not switch accounts.
4. **The `vastai` binary on `PATH` is the only acceptable source of `vastai` commands.** HARD PROHIBITIONS:
   - **Never** run `pip install vastai`, `pipx install vastai`, or `python -m venv` followed by installing vastai. The CLI is already installed.
   - **Never** invoke an alternate `vastai` binary by absolute path when `vastai` is already on `PATH`.
   - **Never** re-implement `vastai` subcommands by hitting `https://console.vast.ai/api/...` or `https://cloud.vast.ai/api/...` directly from `curl`, `python`, `node`, `httpie`, or `requests`. No exceptions.
   - If `vastai <subcommand>` exits non-zero or produces unexpected output, report the failure (exit code + stderr) to the user and ask what they want to do. Do not work around it.
5. **Host actions are visible to renters and impact billing.** Listing, unlisting, price changes, maintenance windows, `defrag machines`, and `cleanup machine` all have side effects on live renters or on your earnings. Before running any of these, confirm with the user — quote the exact command back. Do not run them as a "let me just verify" probe.
6. **`schedule maint` evicts live renters at the start time.** Never schedule a maintenance window without explicit user confirmation of the start date and duration. Active renters on the machine will be terminated when the window opens.
7. **`defrag machines` is disruptive.** It reorganizes the named machines' GPU assignments to free up larger multi-GPU offers — running instances on those machines may be reshuffled or interrupted. The subcommand is `defrag machines` (its own `--help` lies — the usage line reads `vastai defragment machines IDs`, but `vastai defragment machines …` returns `invalid choice` at the parser; only `defrag machines` actually executes). Takes positional machine IDs (e.g. `vastai defrag machines 100 101`); confirm the exact ID list with the user before running.

## Install

```bash
pip install vastai                                       # PyPI (recommended)
```

## Setup / first-time auth

Create an API key at **<https://console.vast.ai/manage-keys/>** (not `cloud.vast.ai/account` — that URL does not exist).

```bash
# Persist locally...
vastai set api-key <YOUR_API_KEY>

# ...or set the env var (per-shell)
export VAST_API_KEY=<YOUR_API_KEY>

vastai show user                                         # Verify auth
```

> **Precedence trap.** Resolution: `--api-key` flag > `$VAST_API_KEY` > stored key. A `VAST_API_KEY` in the shell silently overrides whatever you just persisted with `vastai set api-key`. The CLI prints `⚠️ VAST_API_KEY is set in your environment and overrides the key you just saved` but it's easy to miss. For host work especially — where the persisted key may be a deliberately-scoped monitoring key — check `env | grep VAST_API_KEY` before authenticated calls and `unset` it if you don't want it active.

> **2FA.** If the host account has 2FA enabled, run `vastai tfa login --method-type {totp,sms,email} --code <CODE>` once per shell — the CLI writes a session key to `~/.config/vastai/vast_tfa_key` and uses it transparently. Without an active TFA session, `show machines`, `show earnings`, `show user`, `metrics gpu*`, etc. all return a `401` whose body says *"requires you to have logged in using Two Factor Authentication."* Recommend prefixing the login command with `!` in the Claude transcript so the 6-digit code does not enter conversation history. See the "Common errors" table for the exact pattern.

Machine registration (one-time, on the host machine itself): <https://vast.ai/console/host/setup/>

## Quick start (host onboarding)

```bash
vastai show machines                                     # List your registered machines
vastai self-test machine <MACHINE_ID>                    # Sanity-check before listing
vastai list machine <MACHINE_ID> --price_gpu 0.30        # List for rent at $0.30/GPU/hr
vastai show earnings                                     # Track payouts
```

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

## Filters and queries

**`metrics` subcommands use flags, NOT query-expression strings.** Each accepts a specific set of `--verified {true,false,all}`, `--datacenter {true,false,all}`, and `--rented` / `--gpu` filters — see each command's `--help`.

```bash
vastai metrics gpu --verified true --datacenter true                     # OK
vastai metrics gpu-trends RTX_4090 --verified true                        # GPU name is POSITIONAL on gpu-trends
vastai metrics gpu-locations --gpu "RTX 4090,H100_SXM" --datacenter true
```

**`search` subcommands DO take a query-expression string.** Operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `in`, `notin`. Quote the whole expression because `>` and `<` are shell metacharacters.

```bash
vastai search offers 'gpu_name=RTX_4090 num_gpus=1 verified=true'
vastai search templates 'name=pytorch recommended=true'
```

## Commands

### Machine inventory

```bash
vastai show machines                                     # List all machines you host
vastai show machine <id>                                 # Single machine details
vastai self-test machine <id>                            # Run diagnostics (do this before listing)
vastai reports <id>                                      # Renter-submitted reports for a machine
vastai delete machine <id>                               # Permanently remove from your account
```

### Listing & pricing

```bash
vastai list machine <id> --price_gpu 0.30                # List at $0.30/GPU/hr on-demand
vastai list machine <id> --price_gpu 0.30 --price_inetu 0.05 --price_inetd 0.05 --price_disk 0.10
vastai unlist machine <id>                               # Remove from marketplace (existing renters keep running)

vastai set min-bid <id> --price 0.10                     # Floor price for interruptible/bid rentals
vastai set defjob <id> --image vastai/pytorch:@vastai-automatic-tag --args "..."  # Default job when idle
vastai remove defjob <id>                                # Remove default job
```

**Pricing flags on `list machine`:**
- `--price_gpu <$/hr>` — on-demand GPU price (per GPU per hour)
- `--price_inetu <$/GB>` — internet upload (inbound) bandwidth
- `--price_inetd <$/GB>` — internet download (outbound) bandwidth
- `--price_disk <$/GB/month>` — storage (default: $0.10/GB/month)
- `--price_min_bid <$/hr>` — per-GPU minimum bid floor (alternative to `set min-bid`). NOT `--price_min`.
- `--discount_rate <0-1>` — max long-term prepay discount rate (default 0.4)
- `--min_chunk <int>` — minimum GPUs per rental (default 1)
- `--end_date <date>` / `--duration <e.g. "30 days">` — contract offer expiration
- `--vol_size <GB>` / `--vol_price <$/GB/mo>` — volume contract offer alongside the machine offer

> Price changes apply to **new** rentals only. Existing renters keep the price they signed up at unless they accept a price-increase. Use `vastai show machine <id> --raw | jq .` to verify your current listed prices.

### Maintenance

```bash
# --sdate is UNIX EPOCH SECONDS (not ISO 8601); --duration is HOURS as a float (not "4h").
vastai schedule maint <id> --sdate $(date -u -d '2026-06-01 02:00' +%s) --duration 4 --maintenance_category power
vastai schedule maint <id> --sdate 1812031200 --duration 0.5 --maintenance_category gpu     # 30-min GPU maintenance
vastai cancel maint <id>                                                                    # Cancel a scheduled window
vastai show maints                                                                          # List all scheduled maintenance
```

> `--maintenance_category` accepts `power | internet | disk | gpu | software | other`. Active renters on the machine are terminated when the maintenance window opens. Schedule outside peak hours and notify renters where possible.

### Cleanup & defrag

```bash
vastai cleanup machine <id>                              # Remove expired storage from terminated instances on a single machine
vastai defrag machines <id1> <id2> ...                   # Defragment specific machines. POSITIONAL machine IDs. NOTE: the subcommand is `defrag machines` even though `--help` calls it `defragment machines` — that usage-line wording is misleading; only the abbreviated form executes.
```

> Both are disruptive. `cleanup` is per-machine and reclaims expired-instance disk. `defrag` takes a list of machine IDs and reshuffles GPU assignments on each to make multi-GPU offers possible — running instances may be interrupted. Confirm with the user before running, and always pass the exact ID list.

### Network disks & clusters

```bash
vastai show network-disks                                # List network disks across your machines
vastai add network-disk <machine_id> /mnt/disk1          # First time: positional MACHINES + MOUNT_PATH
vastai add network-disk <machine_id> /mnt/disk1 -d 12345 # Subsequent attach: pass --disk_id (-d) of existing disk
```

Network disks are a host-side storage primitive used internally by the marketplace. **Vast.ai does NOT offer network/shared volumes to renters** — `vastai create network-volume` is CLI plumbing for an unshipped product, not a feature. Don't tell renters they can use network-disks for shared storage.

> The CLI has no `vastai remove network-disk` subcommand — detach/removal is currently console-only at <https://vast.ai/console/host/network-disks/>. Do not call `remove network-disk` (it returns `invalid choice`).

### Earnings & billing

```bash
vastai show earnings                                     # Host earnings summary
vastai show earnings --start-date 2026-01-01 --end-date 2026-02-01
vastai show invoices-v1 --limit <N> --latest-first        # Always pass --limit (see pagination gotcha below); cap is in `--help`
vastai show invoices-v1 --charges --limit <N> --latest-first
vastai show invoices-v1 --invoices --limit <N> --latest-first
vastai show deposit <id>                                 # Reserved-rental deposit info
```

`show invoices` (without `-v1`) is deprecated — use `show invoices-v1`.

> **Pagination gotcha:** `show invoices-v1` prints *"Fetch next page? (y/N)"* after the first page — even with `--raw`. Pass `--limit N --latest-first` on `show invoices-v1` (both flags supported per `vastai show invoices-v1 --help`) to short-circuit the prompt. `show machines` is *not* paginated — `vastai show machines --help` lists no `--limit` flag, so pass none.

### Marketplace metrics

These require the `machine_read` permission group — available to hosts and admins only. They return `401` for pure renter accounts.

```bash
vastai metrics gpu                                       # Current GPU market state
vastai metrics gpu --datacenter true --verified true     # Filter
vastai metrics gpu-trends                                # Historical trends
vastai metrics gpu-trends 'gpu_name=RTX_4090'            # Filter trends
vastai metrics gpu-locations                             # Geographic distribution
```

Use these to spot underserved GPU/region combinations and price your machines competitively.

### Account, API keys, 2FA

```bash
vastai show user                                         # Account info
vastai show api-keys                                     # List API keys
vastai show api-key <id>
vastai create api-key --name "host-monitoring" --permission_file ./perms.json  # Scoped key. --permission_file takes a FILE PATH to JSON, NOT inline JSON. See https://vast.ai/docs/cli/roles-and-permissions
vastai delete api-key <id>
vastai reset api-key                                     # Rotate main key (get new from console)

vastai show audit-logs                                   # Account action history
vastai show ipaddrs                                      # IP address history

# 2FA — see full subcommand reference in the `vastai` (renter) skill
vastai tfa status                                                    # List configured methods
vastai tfa totp-setup                                                # Start TOTP enrollment
vastai tfa activate CODE --secret SECRET -t totp                     # CODE is POSITIONAL; --secret is required; -t selects sms/totp
```

> Use scoped API keys for monitoring scripts — give them read-only permissions so a leaked key can't unlist machines or change prices.

### Teams

```bash
vastai create-team --team-name "ops"                                     # NOTE: hyphenated subcommand + --team-name. NOT `create team --name`.
vastai create-team --team-name "ops" --transfer-credit 50                # Optionally seed from personal credit
vastai destroy team
vastai show members
vastai invite member --email ops-engineer@example.com --role <role-name> # --role, NOT --role-id
vastai remove member <id>
vastai create team-role --name "host-operator" --permissions ./role.json # --permissions takes FILE PATH to JSON, NOT inline
vastai show team-roles
vastai show team-role <id>
vastai update team-role <id> --permissions ./role.json                   # Same — file path
vastai remove team-role <id>
```

Use team-roles to give ops engineers scoped access to your host operations without sharing the main API key.

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `401` + `"...requires you to have logged in using Two Factor Authentication"` in body | Account has 2FA enabled but no current TFA session — affects almost every host read (`show machines`, `show earnings`, `metrics gpu*`, `show user`) | Run `vastai tfa login --method-type {totp,sms,email} --code <CODE>` once per shell. Recommend `!` prefix to keep the 6-digit code out of the transcript. Do NOT rotate the API key — that won't fix it. |
| `401 Unauthorized` / `Invalid or expired API key` (no 2FA wording) | Invalid key OR scoped key lacks the permission set this command requires | First `env | grep VAST_API_KEY` — a shell env var may shadow the stored key. Then `vastai show api-keys --raw` to inspect scope; widen permissions or use your primary key. Only `vastai set api-key <new>` if the key itself is wrong. |
| `Your key lacks the machine_read permission group` | Scoped API key missing host permissions | Use your primary key, or recreate the scoped key passing `--permission_file ./perms.json` to `create api-key`, where the JSON grants the `machine_read` group. (Inline JSON via `--permissions` does not work — the flag takes a file path.) |
| `Machine not found` | Wrong machine ID or machine deleted | `vastai show machines --raw` to list current IDs |
| `Cannot unlist machine with active rentals` | Existing renters on the machine | Wait for rentals to end, or contact support to evict |
| `Maintenance window conflicts with active rental` | Renter has time on the requested window | Choose a later start, or accept that the renter will be evicted |
| `defrag in progress` | Another `defrag machines` operation is already running on this account | Wait for it to finish; `vastai show machines --raw` shows defrag state |

## Pricing & strategy tips

1. **Run `self-test machine` before listing.** Failed self-tests cascade into bad reviews and low rentability.
2. **Set `--price_min`** (or `set min-bid`) so interruptible renters can't underpay your true cost.
3. **Use `metrics gpu-locations`** to spot regions where your GPU is scarce — those command a premium.
4. **Don't undercut `metrics gpu` median by more than ~20%** unless you're seeding rentability; deep undercut races down the whole market.
5. **`set defjob`** lets your machine earn while idle by running a default job (e.g. distributed inference). Test the image works on your hardware first.
6. **Schedule maintenance** in low-utilization windows (check your own historic billing or `metrics gpu-trends` for the GPU in your region).
7. **Use scoped API keys** for monitoring scripts. Never embed your primary key in shell scripts.

## URLs

```
https://vast.ai/console/host/                Host dashboard
https://vast.ai/console/host/setup/          Initial machine registration
https://vast.ai/console/host/billing/        Host payouts
https://console.vast.ai/manage-keys/         Create and manage API keys
https://docs.vast.ai/llms.txt                Full docs index for LLMs
```

## Environment variables

- `VAST_API_KEY` — API key (alternative to `vastai set api-key`)
- `VAST_URL` — API endpoint override (default `https://console.vast.ai`)
