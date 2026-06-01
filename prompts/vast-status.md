---
description: Snapshot of Vast.ai instance status — single instance or all running
argument-hint: [instance-id]
---

Show the current state of one or all Vast.ai instances. Does not poll — this is a single snapshot.

## Steps

1. **If `$1` is empty:** list all instances.
   ```
   vastai show instances-v1 --raw -a
   ```
   `-a` / `--all` auto-fetches every page, sidestepping the interactive `Fetch next page? (y/N)` prompt that otherwise fires under `--raw`. If you only need one page, pass `--limit <N>` instead — read the current per-page cap from `vastai show instances-v1 --help`.

   The response is an object `{instances: [...], instances_found: N}`. Group `instances[]` by `actual_status` (running / loading / exited / stopped / unknown / offline). Show id, label, gpu_name, num_gpus, and `$/hr` for each.

2. **If `$1` is a numeric instance id:** show just that instance.
   ```
   vastai show instance "$1" --raw
   ```
   Report `actual_status`, `intended_status`, `gpu_name`, `cur_state`, `next_state`, and the `$/hr` rate. If `actual_status` is `exited`, `unknown`, or `offline`, flag this as terminal — `vastai destroy instance <id> -y` to stop disk charges.

## Notes

- `--raw` is required to parse the JSON response.
- Status enum: see the `vastai` skill's "Instance status values" section.
- Don't loop without a timeout — terminal states (`exited` / `unknown` / `offline`) signal the instance won't recover.
