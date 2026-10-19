# Bakery App Audit

**Audit date:** 2026-10-19
**Scope:** Architecture, correctness, security, data handling, and automated test coverage.

## Findings

### Addressed locally — Backups silently omitted financial and workflow data

The "full JSON snapshot" exports only products, customers, batches, and sales. It omits:

- Partial payment records
- Customer credits
- Loyalty adjustments
- Expenses
- Favorites and dismissals
- Sale discounts, payment methods, and reservation flags

Restoring from such a backup can produce incorrect balances, loyalty totals, profit figures, and payment histories.

**Evidence:**

- `lib/backup/backup_service.dart:14`
- `lib/backup/backup_service.dart:93`
- `lib/app_state.dart:20`

**Resolution (2026-10-19):** Backup format version 2 now includes every persisted table plus sale discounts, payment methods, and reservation flags. Exports are ZIP archives containing `backup.json` and the authenticated user's actual `product-photos` and `qr-codes` storage objects. Restore remains compatible with standalone version 2 JSON backups; incomplete version 1 backups are rejected.

### Addressed locally — Restore was non-transactional and could overwrite newer data

Restore explicitly accepts an older backup over current data, then updates matched live rows regardless of `updated_at`. Mutations happen row-by-row without a transaction. A malformed record or network failure can therefore leave a partially restored database, while older values may overwrite newer production changes.

**Evidence:**

- `lib/import/backup_restore_service.dart:12`
- `lib/import/backup_restore_service.dart:23`
- `lib/import/backup_restore_service.dart:220`
- `lib/import/backup_restore_service.dart:302`

**Resolution (2026-10-19):** Restore now accepts only complete version 2 documents, validates their structure and references before mutation, obtains a server-side preview, reports newer live-row conflicts, and requires an explicit "Overwrite newer data" confirmation. The actual restore is performed by one PostgreSQL RPC, so any error rolls back the entire operation. Apply the appended `preview_backup_v2` and `restore_backup_v2` SQL before using this flow.

### Addressed locally — Remitted sales remained mutable

Locked/remitted batches reject new customer sales, but `updateSale()` and `deleteSale()` do not check the associated batch lock. Existing transactions can therefore be altered or deleted after remittance, changing already-settled revenue.

**Evidence:**

- Lock enforcement for insertion: `lib/repository/remote_repository.dart:416`
- Missing from update: `lib/repository/remote_repository.dart:454`
- Missing from deletion: `lib/repository/remote_repository.dart:622`

**Resolution (2026-10-19):** Flutter now rejects sale updates/deletes when the current or destination batch is locked or remitted. The appended `trg_prevent_remitted_sale_mutation` PostgreSQL trigger provides authoritative enforcement for every client. The existing reopen-remittance action must run first. Apply the updated SQL for database enforcement.

### Addressed locally — Concurrent devices could oversell inventory

Availability is calculated from the client's last poll and checked before insertion. There is no atomic database-side constraint that locks the batch, totals allocations, and inserts the sale together. Two devices can both see one remaining unit and each sell it.

**Evidence:**

- Client-side calculation: `lib/analytics/batch_calculations.dart:11`
- Direct insert: `lib/repository/remote_repository.dart:437`
- Schema constraints: `docs/supabase_bakery_database_setup.sql:82`

**Resolution (2026-10-19):** Single-sale creation, bulk transaction creation, and quantity-changing sale edits now use PostgreSQL RPCs that lock the affected batch row and recheck allocation inside the same transaction. Accidental or concurrent over-allocation is rejected. The existing owner-confirmed "Continue anyway" workflow passes an explicit override and remains available. Apply `docs/migrations/20261019_atomic_inventory_writes.sql` before running this app version.

### Addressed locally — Application PIN protection was inexpensive to brute-force

The PIN is hashed once with SHA-256 and stored with its salt in `SharedPreferences`. Anyone who extracts local storage can test short PINs offline very quickly. There is also no persistent attempt throttling in this service.

**Evidence:**

- `lib/security/app_lock_service.dart:22`
- `lib/security/app_lock_service.dart:55`

**Resolution (2026-10-19):** New and changed PINs use PBKDF2-HMAC-SHA256 with a random salt and 75,000 iterations. The verifier, salt, iteration count, failed-attempt counter, and lockout deadline are stored in platform secure storage. After three failures, persistent exponential backoff starts at five seconds and caps at five minutes. Existing SHA-256 verifiers are migrated only after the correct legacy PIN is entered. This remains convenience protection, not encryption of app data.

### Addressed — Polling was expensive and created stale decision windows

Previously, ten tables were independently fetched every ten seconds (roughly 60 requests per minute per active client), and a successful write could remain absent from the UI until its next poll.

As of 2026-10-19, background polling is a 30-second fallback using one `get_app_snapshot` RPC (roughly two requests per minute). Every successful repository mutation broadcasts an immediate refresh request, and returning to the foreground triggers the same refresh through `AppState`. All ten read models are returned by the same database statement, removing both the normal post-save wait and cross-table timing gaps while retaining REST polling for networks where the prior realtime WebSocket implementation was unreliable.

**Evidence:**

- Refresh controller and interval: `lib/repository/remote_repository.dart`
- Snapshot RPC migration: `docs/migrations/20261019_app_snapshot_rpc.sql`
- Mutation-triggered refreshes: `lib/repository/remote_repository.dart`
- Foreground refresh: `lib/app_state.dart`

### Addressed locally — Automated coverage was effectively absent

Focused local tests now cover backup/export compatibility and validation,
application lock behavior, remittance guards, inventory calculations, partial
and over-payments, profit/expense date boundaries, and loyalty calculations.
An opt-in disposable-Supabase suite covers database-only guarantees:
concurrent allocation serialization, remitted-sale trigger enforcement, and
transactional restore rollback.

**Evidence:**

- `test/backup_restore_validation_test.dart`
- `test/backup_archive_test.dart`
- `test/remittance_lock_test.dart`
- `test/analytics_regression_test.dart`
- `test/app_lock_service_test.dart`
- `test/integration/supabase_invariants_test.dart`

**Coverage added (2026-10-19):**

- Exporter-to-restore schema compatibility, malformed documents, required
  datasets, duplicate IDs, references, and deliberate v1 rejection.
- Locked, remitted-but-unlocked, and properly reopened mutation states.
- Inventory allocation, deleted rows, partial/over-payments, month boundaries,
  expenses, profit, and loyalty earning/redemption/adjustments.
- Concurrent oversell serialization, remittance enforcement, and failed
  restore rollback against an explicitly enabled disposable Supabase project.

Direct Dart static analysis passes for all new and changed test/production
files. The 20 local unit/regression tests pass. The integration suite is
skipped unless `RUN_SUPABASE_INTEGRATION_TESTS=true` is explicitly supplied.

The three opt-in Supabase integration tests also passed on 2026-10-19 after a
validated recovery backup was saved: concurrent oversell serialization,
remitted-sale mutation enforcement, and transactional rollback of a failed
restore. Test fixtures were removed successfully during teardown.

During backup verification, one live payment referenced a soft-deleted sale.
`docs/migrations/20261019_sale_dependent_cleanup.sql` now repairs existing
rows and adds a trigger: future sale deletion soft-deletes its payments and
detaches (but preserves) independent customer-credit ledger entries.

## Positive Observations

- Supabase tables have row-level security enabled with per-user policies.
- Foreign-key ownership is additionally validated by triggers.
- No service-role secret or embedded private credential was found.
- Storage writes and deletes are scoped to the authenticated user's folder.
- Monetary columns use PostgreSQL `numeric(12,2)`. Dart models remain compatible with `double`, while financial aggregation, comparison, subtraction, and merged-value calculations now round at the boundary and operate as integer centavos.

## Additional data-safety improvements (2026-10-19)

- Newly selected product and QR images are resized and JPEG-compressed before upload. Existing originals are unchanged, while display surfaces continue to request smaller Supabase thumbnails.
- Backup exports now contain the actual product-photo and payment-QR files, not only their public URLs. Database rows restore transactionally; media restores afterward with per-file failures included in the restore report.
- Balance, payment, revenue, expense, remittance, profit, report-total, and merged-sale arithmetic now aggregates and compares integer centavos to avoid binary floating-point drift.

## Verification Notes

The audit findings were subsequently addressed locally. The working tree also
contains pre-existing uncommitted work, which was preserved.

Direct Dart analysis passed for the files changed during remediation, and all
20 local unit/regression tests passed. All three database integration tests
passed against the authenticated account after a validated backup was saved;
the suite remains separately opt-in because it writes isolated temporary rows.
