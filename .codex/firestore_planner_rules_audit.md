# Firestore planner rules audit

This untracked working note records the codebase scan used for the planner rule.
The configured `(default)` database is Standard edition in Firestore native mode.

## Existing access patterns

- `users/{uid}`: owner realtime/get reads for the Worker-owned `budget` map.
- `users/{uid}/{bills|savings|personal}`: owner ordered reads by `createdAt`; writes remain backend-only.
- `users/{uid}/wallet/data`: owner get, realtime listen, transaction create, and merge writes for cash, currency, cards, and loans.
- `users/{uid}.planner`: owner get/realtime read and merge update of one active plan.
- No client Firestore `where` or `limit` queries are used. Entry queries use only descending `orderBy('createdAt')`.

## Planner schema

The planner map has exactly 13 keys: a bounded plan id, period enum, start/end timestamps, three boolean/amount pairs, positive total, recent creation timestamp, and alert eligibility. Disabled amounts must be zero; enabled amounts must be positive and bounded. The total must match the three category amounts within one cent.

## Adversarial checks

- Public and cross-user reads/writes fail because every grant requires the authenticated path owner.
- Updates that touch `budget` or any non-planner user field fail the affected-keys check.
- Missing, extra, wrong-type, oversized, negative, zero-enabled, invalid-period, reversed-date, stale-createdAt, and mismatched-total planner maps fail validation.
- Planner creates may contain only the planner field. Deletes remain denied.
- The plan id and timestamps are replaced as part of a new plan, so they are intentionally not immutable across replacements.
- Subcollections and paths outside the existing explicit matches remain deny-all.

The rules were not deployed and no production data was accessed.
