# Self-test plan — `vast-codex-plugin`

A runbook to verify the plugin end-to-end. Behavioral phases (1–4) are run inside a live `codex` session by pasting prompts and observing responses; install/mechanics phases (0, 5) are automated. Launches real GPU instances and incurs real charges.

---

## Budget

- **Hard cap:** $2.00 of Vast credit.
- **Typical spend:** $0.20–$0.50 (a few minutes of RTX 4090 at ~$0.30/hr).
- **Abort the run if** pre-flight balance is under $2.

---

## Prerequisites

```bash
# 1. vastai CLI
vastai --version                           # → 1.0.13 or newer

# 2. Vast API key in env (must be set BEFORE codex starts)
echo "${VAST_API_KEY:?must export VAST_API_KEY first}"

# 3. codex CLI
which codex || { echo "codex CLI not installed — install per https://developers.openai.com/codex and re-run"; exit 1; }
codex --version

# 4. Working tree on the right branch
cd /Users/will/freelance/work/vast-plugins/workspace/repos/vast-codex-plugin
git rev-parse --abbrev-ref HEAD            # → skills/split-renter-host
PLUGIN=$PWD
```

---

## Phase 0 — Install ($0, automated)

```bash
./install.sh --dry-run                     # preview
./install.sh --force                       # install for real

# Verify both skills landed
[ -f ~/.agents/skills/vastai/SKILL.md ]      && echo "renter skill OK"      || echo "RENTER SKILL MISSING"
[ -f ~/.agents/skills/vastai-host/SKILL.md ] && echo "host skill OK"        || echo "HOST SKILL MISSING"

diff -q "$PLUGIN/skills/vastai/SKILL.md"      ~/.agents/skills/vastai/SKILL.md
diff -q "$PLUGIN/skills/vastai-host/SKILL.md" ~/.agents/skills/vastai-host/SKILL.md

# All 5 prompts landed
for p in vast-setup vast-status vast-cost vast-search vast-launch; do
  [ -f ~/.codex/prompts/$p.md ] && echo "prompt $p OK" || echo "PROMPT $p MISSING"
done

# Restart codex now so it picks up the new skills/prompts
```

---

## Pre-flight ($0)

```bash
RUN_ID=codex-$(date +%Y%m%d-%H%M%S)
OUT=/Users/will/freelance/work/vast-plugins/workspace/test-results/$RUN_ID
mkdir -p "$OUT"

vastai show user --raw         > "$OUT/baseline-user.json"
vastai show instances-v1 --raw > "$OUT/baseline-instances.json"
START_BAL=$(jq -r '.credit' "$OUT/baseline-user.json")
echo "Starting balance: \$$START_BAL"
[ "$(echo "$START_BAL < 2" | bc)" -eq 1 ] && { echo "BUDGET FAIL"; exit 1; }

cat > "$OUT/results.md" <<EOF
# Codex self-test results — $RUN_ID

## Phase 1 — Knowledge probes (text only)
- [ ] p1.1 API key URL → response mentions console.vast.ai/manage-keys/
- [ ] p1.2 Shared volumes → response says Vast doesn't offer / only local / use S3
- [ ] p1.3 SSH command → response does NOT say \`ssh \$(vastai ssh-url ...)\`; shows --raw parsing
- [ ] p1.4 Onstart 6000 chars → response identifies the arg-length cap (reads it from the API 400/3471 error) + gzip workaround
- [ ] p1.5 Spot eviction → response identifies spot eviction; mentions change bid

## Phase 2 — Command generation (vastai allowed, read-only)
- [ ] p2.1 Balance → agent ran \`vastai show user --raw\`
- [ ] p2.2 List instances → \`vastai show instances-v1 --raw --limit ...\`
- [ ] p2.3 Search 4090 → \`vastai search offers ... RTX_4090 ... --raw\` with NO \`-n\`
- [ ] p2.4 Kill 99999 → \`vastai destroy instance 99999 -y\`
- [ ] p2.5 Set env var → \`vastai create env-var HF_TOKEN_SELFTEST hf_xxxxx_literal --raw\`
- [ ] p2.6 Show machines → \`vastai show machines --raw\` (vastai-host loaded)

## Phase 3 — End-to-end lifecycle
- [ ] p3.1 create-instance command included --disk
- [ ] p3.2 create-instance command included --ssh
- [ ] p3.3 create-instance command included --direct
- [ ] p3.4 create-instance command included --cancel-unavail
- [ ] p3.5 destroy used -y
- [ ] p3.6 no leftover instances with label selftest-$RUN_ID-e2e

## Phase 4 — Host skill routing (expect 401)
- [ ] p4.1 host-metrics ran \`vastai metrics gpu*\`
- [ ] p4.2 host-machines ran \`vastai show machines\`
- [ ] p4.3 On 401, agent suggested checking permissions (NOT "reset api-key")
EOF

cat > "$OUT/cleanup.sh" <<EOF
#!/usr/bin/env bash
vastai show instances-v1 --raw --limit 200 \\
  | jq -r '.instances[]? | select(.label | tostring | startswith("selftest-$RUN_ID-")) | .id' \\
  | xargs -I{} vastai destroy instance {} -y --raw
vastai delete env-var HF_TOKEN_SELFTEST --raw 2>/dev/null || true
EOF
chmod +x "$OUT/cleanup.sh"
```

---

## Launch codex

Open codex in your normal way (CLI or IDE extension). Inside the session, sanity-check that the prompts are listed:

```
/prompts:vast-setup    /prompts:vast-status    /prompts:vast-cost
/prompts:vast-search   /prompts:vast-launch
```

If they don't appear, the install didn't propagate or codex didn't pick up the new prompts — restart codex and re-check `~/.codex/prompts/`.

---

## Phase 1 — Knowledge probes (in codex session, $0)

Paste each prompt exactly. Save the response text into `$OUT/transcripts/p1-<slug>.txt`, tick the box in `$OUT/results.md`.

| # | Prompt | PASS if response mentions |
|---|---|---|
| 1.1 | *What URL do I go to to create a Vast.ai API key?* | `console.vast.ai/manage-keys/` (NOT `cloud.vast.ai/account`) |
| 1.2 | *Can I share a single volume across multiple Vast.ai instances at the same time?* | "Vast doesn't offer" / "only local volumes" / suggests S3 via `cloud copy`. **FAIL** if it suggests `create network-volume`. |
| 1.3 | *Show me the exact shell command to ssh into Vast instance 12345 using the vastai CLI.* | Parses `--raw` (`ssh_host`, `ssh_port`) or uses awk on the URL. **FAIL** if it says `ssh $(vastai ssh-url 12345)`. |
| 1.4 | *I have a 6000-character `onstart-cmd` script and the instance never starts. What's wrong?* | Identifies an arg-length cap; says to read the live value from the API `400/3471 Invalid args: len(args) > N` error rather than baking in a literal limit; recommends gzip+base64 or `--onstart FILE` as the workaround. |
| 1.5 | *`vastai show instance` says `intended_status=running` but `actual_status=stopped`. What's going on?* | Identifies spot eviction; mentions `change bid` or `--bid_price` |

---

## Phase 2 — Command generation (in codex session, $0)

Same session. Codex shows each shell tool call it makes — copy the `vastai` lines.

| # | Prompt | PASS if agent ran |
|---|---|---|
| 2.1 | *What's my Vast.ai credit balance?* | `vastai show user --raw` |
| 2.2 | *Show me a JSON list of my running instances.* | `vastai show instances-v1 --raw …` **with `--limit`** |
| 2.3 | *Find the cheapest verified RTX 4090 under $0.40/hr with `compute_cap>=70`.* | Agent recognizes the user-supplied `70` is wrong (encoding is `cuda_cap * 100`) and runs `vastai search offers … RTX_4090 … compute_cap>=700 … --raw` with **no** ` -n ` or `--no-default`. FAIL if the search uses `compute_cap>=70` verbatim. |
| 2.4 | *Kill Vast instance 99999.* | `vastai destroy instance 99999 -y` (404 from Vast is expected) |
| 2.5 | *Create a Vast account env var called `HF_TOKEN_SELFTEST` with the value `hf_xxxxx_literal`.* | `vastai create env-var HF_TOKEN_SELFTEST hf_xxxxx_literal --raw` (**literal value**) |
| 2.6 | *Show me my Vast.ai hosted machines.* | `vastai show machines --raw` — and `vastai-host` skill loaded (not `vastai`) |

Cleanup the env var: `vastai delete env-var HF_TOKEN_SELFTEST --raw`.

---

## Phase 3 — End-to-end lifecycle ($0.20–$0.50)

Same codex session. Paste this single prompt — substitute `<RUN_ID>`:

> *You are validating the vast-codex-plugin against a live account. Do all of this end-to-end and report what happened:*
>
> *1. Find the cheapest verified single-GPU offer with `compute_cap>=700` and `rentable=true` under $0.50/hr. Prefer RTX 4090 but accept anything cheaper that meets those filters.*
> *2. Launch it with image `vastai/pytorch:@vastai-automatic-tag`, `--disk 20`, `--ssh`, `--direct`, `--cancel-unavail`, and `--label 'selftest-<RUN_ID>-e2e'`.*
> *3. Poll `show instance` with a 10-minute deadline until `actual_status==running`. If `actual_status` hits `exited`/`unknown`/`offline`, destroy with `-y` and report failure.*
> *4. Once running, run `nvidia-smi --query-gpu=name,driver_version --format=csv,noheader` via `vastai execute`. Capture stdout.*
> *5. Destroy the instance with `-y`. Verify via `show instances-v1 --raw --limit 50` that no instance with that label remains.*
> *6. Report: offer id picked, instance id, dph_total, elapsed seconds, the nvidia-smi line, final destroy confirmation, AND the EXACT vastai create-instance command you ran (so I can verify the flags).*

**In a side terminal, watch progress:**

```bash
watch -n 5 "vastai show instances-v1 --raw --limit 50 | jq '[.instances[] | select(.label | tostring | startswith(\"selftest-$RUN_ID-\"))] | .[] | {id, actual_status, label, dph_total}'"
```

**After it finishes** — paste the agent's reported create-instance command into `$OUT/p3-create.txt`, then:

```bash
grep -q -- '--disk'            "$OUT/p3-create.txt" && echo "p3.disk PASS"            || echo "p3.disk FAIL"
grep -q -- '--ssh'             "$OUT/p3-create.txt" && echo "p3.ssh PASS"             || echo "p3.ssh FAIL"
grep -q -- '--direct'          "$OUT/p3-create.txt" && echo "p3.direct PASS"          || echo "p3.direct FAIL"
grep -q -- '--cancel-unavail'  "$OUT/p3-create.txt" && echo "p3.cancel-unavail PASS"  || echo "p3.cancel-unavail FAIL"

LEFTOVER=$(vastai show instances-v1 --raw --limit 200 | jq "[.instances[]? | select(.label==\"selftest-$RUN_ID-e2e\")] | length")
[ "$LEFTOVER" = "0" ] && echo "p3.no-leftover PASS" || echo "p3.no-leftover FAIL ($LEFTOVER leftover)"
```

**Known false positive:** host self-destruct (CDI errors, container shim) is a real Vast bug. If the agent correctly destroys+reports, that's still a P3 PASS. Re-run on a different offer to exercise nvidia-smi.

---

## Phase 4 — Host skill routing ($0, expect 401)

Same codex session.

| # | Prompt | PASS if |
|---|---|---|
| 4.1 | *What's the going hourly rate for RTX 4090s in US datacenters right now according to Vast.ai's marketplace metrics?* | Agent ran `vastai metrics gpu` (or `metrics gpu-locations`); on 401, suggested checking permission scope with `vastai show api-keys --raw` (NOT "reset api-key") |
| 4.2 | *List my Vast.ai hosted machines.* | Agent ran `vastai show machines --raw`; same scoped-permission guidance on 401 |

---

## Phase 5 — Plugin install mechanics (automated, $0)

```bash
# install.sh syntax
bash -n "$PLUGIN/install.sh" && echo "p5.install-syntax PASS" || echo "p5.install-syntax FAIL"

# Files in repo
[ -f "$PLUGIN/skills/vastai/SKILL.md" ]      && echo "p5.skill-renter PASS" || echo "p5.skill-renter FAIL"
[ -f "$PLUGIN/skills/vastai-host/SKILL.md" ] && echo "p5.skill-host PASS"   || echo "p5.skill-host FAIL"
for p in vast-setup vast-status vast-cost vast-search vast-launch; do
  [ -f "$PLUGIN/prompts/$p.md" ] && echo "p5.prompt-$p PASS" || echo "p5.prompt-$p FAIL"
done

# Install propagated to ~/.agents and ~/.codex
diff -q "$PLUGIN/skills/vastai/SKILL.md"      ~/.agents/skills/vastai/SKILL.md      && echo "p5.installed-renter PASS" || echo "p5.installed-renter FAIL"
diff -q "$PLUGIN/skills/vastai-host/SKILL.md" ~/.agents/skills/vastai-host/SKILL.md && echo "p5.installed-host PASS"   || echo "p5.installed-host FAIL"
for p in vast-setup vast-status vast-cost vast-search vast-launch; do
  diff -q "$PLUGIN/prompts/$p.md" ~/.codex/prompts/$p.md >/dev/null && echo "p5.installed-$p PASS" || echo "p5.installed-$p FAIL"
done
```

Manual check inside codex: type `/prompts` (or your codex's equivalent) and confirm all five `vast-*` prompts are listed. Tick this box:

```
- [ ] p5.prompts-listed → /prompts shows all five vast-* entries
```

---

## Final report

```bash
{
  echo "# Self-test report — $RUN_ID"
  echo
  echo "**Plugin:** vast-codex-plugin"
  echo "**Branch:** $(git -C "$PLUGIN" rev-parse --abbrev-ref HEAD) ($(git -C "$PLUGIN" rev-parse --short HEAD))"
  echo "**Codex version:** $(codex --version 2>&1 | head -1)"
  echo "**Started:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  END_BAL=$(vastai show user --raw | jq -r .credit)
  echo "**Balance:** \$$START_BAL → \$$END_BAL (spent \$$(echo "$START_BAL - $END_BAL" | bc))"
  echo
  cat "$OUT/results.md"
} > "$OUT/REPORT.md"

"$OUT/cleanup.sh"

vastai show instances-v1 --raw --limit 200 \
  | jq "[.instances[]? | select(.label | tostring | startswith(\"selftest-$RUN_ID-\"))] | length" \
  | grep -q '^0$' && echo "CLEAN" || echo "LEAK — manual cleanup needed"
```

---

## Pass/fail matrix

| Phase | Tests | Automated? | Failure means |
|---|---:|:---:|---|
| 0 Install | 7 | yes | install.sh broken or files missing |
| 1 Knowledge | 5 | manual (chat) | Skill content didn't surface |
| 2 Command-gen | 6 | manual (chat) | Agent dropped a flag or used `-n` |
| 3 E2E | 6 | partly | Real launch broken or critical flags missing |
| 4 Host routing | 3 | manual (chat) | Wrong skill loaded or 401 handling regressed |
| 5 Mechanics | 14 | yes | Layout broken or install didn't propagate |

**Total: 41 checks.** ≥37/41 (≥90%) to publish.

---

## Manual followup (always)

```bash
vastai show instances-v1 --raw --limit 200 \
  | jq -r '.instances[]? | select(.label | tostring | startswith("selftest-")) | "\(.id)  \(.label)  \(.actual_status)"'
```

Any output = leak. `vastai destroy instance <id> -y --raw` to clean up.
