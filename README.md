# vast-codex-plugin

A [Codex](https://developers.openai.com/codex) plugin for [Vast.ai](https://vast.ai). Rent, launch, monitor, and tear down GPU instances — plus volumes, serverless endpoints, and billing.

- **Five custom prompts** wrap common rental operations with safe defaults.
- **A bundled `vastai` skill** gives Codex full command-reference knowledge of the `vastai` CLI, so anything the prompts don't cover (ssh, copy, logs, exec, destroy, volumes, serverless, environment variables, …) works through natural language.

## Custom prompts

| Prompt | What it does |
|---|---|
| `/prompts:vast-setup [api-key]` | Stores your API key, registers your SSH public key with Vast, and verifies the credential against `vastai show user`. Run this once before anything else — launching an instance before an SSH key is registered produces an unreachable host. |
| `/prompts:vast-status [instance-id]` | Snapshot of a single instance or all of yours. Flags terminal states (`exited`, `unknown`, `offline`) so polling loops actually terminate. |
| `/prompts:vast-cost` | Account balance, current burn rate ($/hr across active instances), and projected 24-hour spend. |
| `/prompts:vast-search [filter]` | Finds the cheapest **rentable** offers matching a filter, sorted by total $/hr. Recognises `"spot"` / `"bid"` in the filter and switches to interruptible bid-mode pricing automatically. |
| `/prompts:vast-launch OFFER=<id> [IMAGE=...] [DISK=N] [LABEL=...]` | Launches an offer with sensible defaults: `pytorch/pytorch:@vastai-automatic-tag`, 20 GB disk, direct SSH, JSON output. Parses the returned `new_contract` ID so subsequent commands can reference it. |

Every `vastai` invocation includes `--raw` so responses come back as parseable JSON.

## Natural language

The bundled `vastai` skill auto-loads when Codex detects Vast-related intent — GPU rental, SSH, copying files to/from an instance, env vars, billing, serverless, volumes, and so on.

> *"Find a verified 4090 under $0.40/hr and launch it with pytorch."*
>
> *"SSH into instance 12345 and tail `/var/log/nvidia-installer.log`."*
>
> *"Set `HF_TOKEN` to `hf_xxxxx` on my running instance."*
>
> *"Destroy everything except instance 12345."*

To force the skill to load explicitly, mention it by name (*"using the vastai skill, …"*).

## Install

### Prerequisites

```bash
pip install vastai          # the vastai CLI itself (1.0.x or newer)
vastai --version
```

A working Vast.ai account; grab an API key from <https://cloud.vast.ai/account>.

### From source

```bash
git clone https://github.com/vast-ai/vast-codex-plugin.git
cd vast-codex-plugin
./install.sh
```

That copies the skill into `~/.agents/skills/vastai/` and the prompts into `~/.codex/prompts/`. Restart your Codex session (CLI or IDE extension) to pick them up.

`./install.sh --force` to upgrade in place. `./install.sh --dry-run` to preview.

## First run

```
/prompts:vast-setup
```

You'll be prompted for an API key from <https://cloud.vast.ai/account>. The walkthrough then registers your SSH public key (`~/.ssh/id_ed25519.pub` by default, falling back to `id_rsa.pub`) and verifies the credential by querying your user record.

## Layout

```
vast-codex-plugin/
├── install.sh                   # installs into ~/.agents/ and ~/.codex/
├── skills/vastai/
│   └── SKILL.md                 # vendored from vast-ai/vast-cli
├── prompts/
│   ├── vast-setup.md            # /prompts:vast-setup
│   ├── vast-status.md           # /prompts:vast-status
│   ├── vast-cost.md             # /prompts:vast-cost
│   ├── vast-search.md           # /prompts:vast-search
│   └── vast-launch.md           # /prompts:vast-launch
├── VENDORED_FROM.md             # pins the upstream SHA
└── PATCHES.md                   # local deltas pending upstream PRs
```

## License

MIT — see [LICENSE](./LICENSE). `SKILL.md` is vendored from [`vast-ai/vast-cli`](https://github.com/vast-ai/vast-cli) (also MIT); local edits are tracked in [`PATCHES.md`](./PATCHES.md) for upstream propagation.
