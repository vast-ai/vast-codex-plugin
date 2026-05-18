---
description: Search Vast.ai GPU offers by filter — returns the cheapest matching rentable offers
argument-hint: [filter]
---

Search the Vast.ai marketplace for GPU offers and show the cheapest matches.

## Steps

1. **Build the filter.** If `$ARGUMENTS` is empty, default to:
   ```
   'num_gpus=1 rentable=true verified=true'
   ```
   Otherwise pass `$ARGUMENTS` through verbatim, ensuring `rentable=true` is present (add it if missing).

2. **Run the search**, cheapest-first:
   ```
   vastai search offers <FILTER> -o 'dph_total' --raw
   ```

3. **Show the top 10 results** as a table with: offer id, `gpu_name` × `num_gpus`, `dph_total` ($/hr), `dlperf` (perf score), `geolocation`. Don't print all rows.

4. If the prompt mentions "spot", "bid", or "cheapest interruptible", use `--type bid` instead of the default on-demand.

5. If results are empty, suggest relaxing the filter.

## Examples

| Invocation | Filter |
|---|---|
| `/prompts:vast-search` | `'num_gpus=1 rentable=true verified=true'` |
| `/prompts:vast-search gpu_name=RTX_4090` | `'gpu_name=RTX_4090 rentable=true'` |
| `/prompts:vast-search gpu_name=H100 num_gpus>=4` | `'gpu_name=H100 num_gpus>=4 rentable=true'` |

## Notes

- `--raw` is mandatory.
- Full query syntax: `vastai` skill § "Search".
