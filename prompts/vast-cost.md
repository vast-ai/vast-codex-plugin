---
description: Snapshot of Vast.ai spend — account balance, active $/hr, recent invoices
argument-hint:
---

Report current Vast.ai spend at a glance.

## Steps

1. **Account balance.** Run:
   ```
   vastai show user --raw
   ```
   Report `credit` (current balance) and `email`.

2. **Active spend rate.** Run:
   ```
   vastai show instances-v1 --raw
   ```
   From the response object, sum `instances[].dph_total` (dollars per hour) across rows whose `actual_status` is `running`. Report as `$/hr` and project a 24h cost.

3. **Recent invoices (optional).** If the user wants a longer view:
   ```
   vastai show invoices-v1 -c --raw
   ```
   The `-c` flag selects "charges" (use `-i` for paid invoices). Summarize `results[]` over the last three months.

## Notes

- `--raw` is required on every call.
- Use `show invoices-v1`, **not** the legacy `show invoices`.
- Full billing surface: `vastai` skill § "Account & Billing".
