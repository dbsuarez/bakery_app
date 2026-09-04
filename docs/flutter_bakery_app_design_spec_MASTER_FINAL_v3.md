# Bakery Order & Remittance Tracker — MASTER FINAL v3
### Consolidated and reviewed design specification for Claude Code
### Flutter mobile local-first + Flutter Web Supabase-direct + Supabase multi-device sync

---

## 1. Executive Decision

Build one Flutter project with two data modes:

- **Android phone/tablet**: local-first Drift/SQLite database, fully usable offline, synchronized with Supabase.
- **Computer browser**: Flutter Web app with no local database; every read/write goes directly to Supabase.
- **Cloud**: Supabase Postgres, Auth, Realtime, and Storage.
- **Web hosting**: Netlify. Build locally with `flutter build web --release`, then upload `build/web`; Git-connected deployment can be added later.
- **Migration during development**: no live Google Sheets sync. Use a safe, re-runnable XLSX import into mobile Drift, then let mobile sync changes to Supabase.

This is intentionally a small app. Use a simple repository, provider, Drift DAOs, and a single SyncService. Do not introduce a large Clean Architecture framework, background workers, or unnecessary abstractions.

---

## 2. Source Data Interpretation

Original sheets:

- `tblProduct` → `products`.
- `tblCustomers` → `customers`.
- `tblRemittance` → `batches`.
- `tblTransactions` → `sales`.

`tblTransactions.batch_id` links every transaction to a remittance/batch row. Preserve the batch reference and the transaction date for every sale.

### Important source findings

- The workbook's visible data ends at 14 products, approximately 80 customers, 37 remittance/batch rows, and 283 populated transactions; the remaining worksheet rows are blank formatting rows and must not be imported.
- The current transaction sheet has no explicit quantity column. New app records must add `quantity`; legacy records should default to quantity 1 unless quantity is reliably inferred.
- Existing `amount` values represent more than simple unit price × one unit: bulk purchases, discounts, freebies, and manual adjustments exist. Keep both `quantity` and editable `amount`.
- Pseudo-customers such as `Dante` and `Unsold` need classification rather than being treated as normal customers.
- Remittance row id 7 appears suspicious: Crinkles (B), count 80, price 4, total 320. Since the arithmetic still equals the total, validation must also compare against transaction quantities/rows and flag implausible price/count combinations for review.
- The workbook has trailing blank rows, including rows where only `paid=False` remains. Skip any row without a valid transaction ID, batch ID, product, and customer.

Do not silently “fix” historical data. Import it, flag it, and let the user review it.

---

## 3. Devices and Data Architecture

### Mobile local-first mode

Each Android device has its own local SQLite database:

1. UI reads local Drift streams.
2. User writes local data immediately.
3. Changed rows receive `is_dirty = true`.
4. SyncService pushes dirty rows to Supabase when online.
5. Supabase Realtime delivers changes made by other devices.
6. App resume and manual Sync Now perform cursor-based reconciliation.

Phone and tablet therefore remain useful during weak or absent connectivity.

### Web direct mode

The web app has no Drift instance, SQLite, WASM, IndexedDB cache, or local data copy. It requires internet and uses Supabase directly. Realtime updates in-memory streams.

### Shared UI repository

```dart
abstract class BakeryRepository {
  Stream<List<Product>> watchProducts();
  Stream<List<Customer>> watchCustomers();
  Stream<List<Batch>> watchBatches();
  Stream<List<Sale>> watchSales();

  Future<void> createProduct(Product product);
  Future<void> createCustomer(Customer customer);
  Future<void> createBatch(Batch batch);
  Future<void> addSingleSale(Sale sale);
  Future<void> addBatchTransactions(
    int batchId,
    List<BatchTransactionEntry> entries,
  );
  Future<void> markSalePaid(int saleId, DateTime paymentDate);
  Future<void> markSaleUnpaid(int saleId);
  Future<void> markBatchRemitted(int batchId, DateTime dateRemitted);
  Future<void> unlockBatch(int batchId);
}
```

`LocalRepository` implements this using Drift. `RemoteRepository` implements it using Supabase. Screens must not contain platform-specific database logic.

Use `provider` with one repository/change-notifier layer. Keep the folder structure flat and understandable.

---

## 4. Local Drift Schema

Use Drift Dart table definitions rather than manually maintaining raw SQL only. The logical schema is:

```sql
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_id TEXT,
  title TEXT NOT NULL UNIQUE,
  image_url TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  is_dirty INTEGER NOT NULL DEFAULT 1,
  is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_id TEXT,
  name TEXT NOT NULL,
  phone TEXT,
  is_archived INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  is_dirty INTEGER NOT NULL DEFAULT 1,
  is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_id TEXT,
  legacy_id INTEGER UNIQUE,
  product_id INTEGER NOT NULL REFERENCES products(id),
  batch_date TEXT NOT NULL,
  count_produced INTEGER NOT NULL,
  unit_price REAL NOT NULL,
  unit_cost REAL NOT NULL DEFAULT 0,
  total_value REAL NOT NULL,
  remitted INTEGER NOT NULL DEFAULT 0,
  date_remitted TEXT,
  locked INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  is_dirty INTEGER NOT NULL DEFAULT 1,
  is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE sales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_id TEXT,
  legacy_id INTEGER UNIQUE,
  batch_id INTEGER NOT NULL REFERENCES batches(id),
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  sale_date TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  amount REAL NOT NULL,
  paid INTEGER NOT NULL DEFAULT 0,
  date_paid TEXT,
  sale_type TEXT NOT NULL DEFAULT 'customer_sale',
  notes TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  is_dirty INTEGER NOT NULL DEFAULT 1,
  is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE sync_meta (
  table_name TEXT PRIMARY KEY,
  last_synced_at TEXT
);

CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

Indexes:

```sql
CREATE INDEX idx_sales_batch ON sales(batch_id);
CREATE INDEX idx_sales_customer ON sales(customer_id);
CREATE INDEX idx_batches_product ON batches(product_id);
```

Use `image_url`, not a local file path. Product images live in Supabase Storage and must display on every device.

`app_settings` is local-only and is never synchronized.

---

## 5. Supabase Schema, Security, Storage, and Realtime

Create matching Postgres tables with UUID primary keys. Each row must contain `user_id` referencing `auth.users(id)`. Enable RLS on every application table and create owner policies using `auth.uid() = user_id`.

Required fields:

- `products`: id, user_id, title, image_url, updated_at, is_deleted.
- `customers`: id, user_id, name, phone, is_archived, updated_at, is_deleted.
- `batches`: id, user_id, product_id, batch_date, count_produced, unit_price, unit_cost, total_value, remitted, date_remitted, locked, updated_at, is_deleted.
- `sales`: id, user_id, batch_id, customer_id, sale_date, quantity, amount, paid, date_paid, sale_type, notes, updated_at, is_deleted.

Use a Supabase Storage bucket named `product-photos`. Store its public URL in `products.image_url`.

Enable the four tables in `supabase_realtime` replication. Confirm this in the Supabase dashboard because `alter publication ... add table` can fail if a table is already present.

Security requirements:

- Never put a Supabase service-role key in the Flutter app.
- Use only the public anon key in the client.
- Require authentication before loading application data.
- Keep RLS enabled before testing the client.
- Add Storage policies so only the authenticated owner can upload/update/delete product photos; public read is acceptable if the bucket is intentionally public.
- Add indexes on `user_id`, `updated_at`, and foreign keys for sync/query performance.
- Add a database check constraint for positive `quantity`, nonnegative amounts where appropriate, and valid `sale_type` values.

Important: the final SQL migration must be idempotent or clearly marked as a fresh-project script. Do not blindly rerun `CREATE TABLE` or duplicate triggers/policies.

---

## 6. Sync Design

### Mobile push

- Query dirty rows in dependency order: products/customers → batches → sales.
- Insert rows without `remote_id`, save the returned Supabase UUID.
- Update rows with `remote_id`.
- Clear dirty only after success.
- Keep failed rows dirty and expose the failure in Sync Diagnostics.

### Mobile pull

- Store one cursor per table in `sync_meta`.
- Pull records newer than each cursor and scoped to the authenticated user.
- Upsert local rows by `remote_id`.
- Apply remote changes only when remote `updated_at` is newer.
- Hide soft-deleted rows.
- Advance the cursor only after the full table pull succeeds.

### Realtime

Use Supabase Realtime as the primary cross-device update path. On an event:

- Ignore events belonging to another user.
- Merge the record into local Drift if the remote timestamp is newer.
- Do not overwrite a dirty local row without a conflict decision.
- If an edit form is open, show a snackbar and offer refresh.

### Conflict policy

Use last-write-wins by server `updated_at` for this single-owner application, but preserve dirty local edits when they are newer or not yet pushed. Avoid using device clocks as the only authority; let Supabase's trigger-generated timestamp be authoritative after a successful push.

### Web

RemoteRepository performs direct Supabase CRUD and uses Realtime to refresh in-memory lists. It does not use mobile dirty flags or local sync cursors.

### Status UI

Mobile: Synced, Pending N changes, Offline, or Sync Error. Web: Online, Offline, or Server Error. Include a manual Sync Now button and a diagnostics view showing the last successful push/pull and failed items.

---

## 7. Core Business Rules

1. `total_value = count_produced × unit_price`; recompute when an unlocked batch changes.
2. New sale amount defaults to `quantity × batch.unit_price`.
3. Allow amount override for bulk pricing, discounts, freebies, or corrections.
4. Quantity is a positive integer.
5. Warn, but do not block, when allocated quantity exceeds produced quantity; require explicit confirmation.
6. Customer balances include only unpaid `customer_sale` rows.
7. Batch remaining quantity = produced quantity − allocated `customer_sale` quantity.
8. Marking a sale paid sets `paid = true` and `date_paid` to the chosen date, defaulting to today.
9. Marking a sale unpaid sets `paid = false` and clears `date_paid`.
10. Marking a batch remitted sets `remitted = true`, `date_remitted`, and `locked = true` atomically.
11. Locked batch metadata is read-only. Sales payment status remains editable.
12. Unlocking a batch requires confirmation; reverting remittance is a separate confirmation.
13. Estimated profit = `total_value − (count_produced × unit_cost)`.
14. Never hard-delete synchronized rows; use soft deletion.
15. `sale_type` values: `customer_sale`, `unsold`, `internal_consumption`.
16. `Unsold` and `Dante` legacy rows must not pollute normal customer analytics.

---

## 8. Batch Add Transactions — Primary Workflow

### Purpose

Enter one distribution batch quickly by selecting one batch, multiple customers, and each customer's quantity. The selected batch determines the product and unit price.

### Flow

1. Tap **Batch Add Transactions**.
2. Select a batch.
3. Automatically show its product, date, unit price, produced count, allocated count, and remaining count.
4. Search/select multiple customers.
5. Set each customer's quantity.
6. Choose default Paid or Unpaid.
7. Choose payment date if Paid; default today.
8. Review generated rows.
9. Save atomically.

Example:

```text
Batch: 2026-09-02 — Crinkles Red Velvet (S)
Product: Crinkles Red Velvet (S)
Unit price: ₱90
Produced: 10 · Allocated: 4 · Remaining: 6

Search customers...

☑ Faye     [−] 1 [+]   Standard ₱90   Final ₱90
☑ Jing     [−] 2 [+]   Standard ₱180  Final ₱180
☑ Karen    [−] 1 [+]   Standard ₱90   Final ₱90

Default payment: [Unpaid]
Selected: 3 customers · 4 units · ₱360
Remaining after save: 2

[Review]              [Save 3 Transactions]
```

Required controls:

- Search by customer name.
- Quantity stepper and quick buttons 1/2/5/10.
- Select All Visible and Clear All.
- Highlight customers already present in this batch.
- Warn before exceeding available batch units.
- Allow explicit override.
- Global default payment state with individual overrides.
- Automatic date-paid behavior.
- Standard amount plus editable final amount.
- Optional row notes.

### Duplicate handling

If a manually selected customer already has a transaction in the batch, do not silently duplicate. Offer:

- Add another transaction.
- Increase existing quantity.
- Cancel.

Do preserve duplicate legacy spreadsheet rows during migration.

### Data object

```dart
class BatchTransactionEntry {
  final int customerId;
  final int quantity;
  final double amount;
  final bool paid;
  final DateTime? datePaid;
  final String? notes;
}
```

### Atomic save

Mobile: insert all rows inside one Drift transaction. Web: send one multi-row Supabase insert or use a secure RPC if needed. Validate every row before writing.

After saving:

- Update allocated/remaining counts.
- Refresh dashboard and balances.
- Mark mobile rows dirty.
- Show one summary notification.
- Celebrate only meaningful milestones with confetti.

---

## 9. Payment Status and Date Paid

Every transaction stores independent payment status.

| Action | paid | date_paid |
|---|---:|---|
| Mark Paid | true | Selected date, default today |
| Mark Unpaid | false | null |
| Historical payment | true | User-selected historical date |

The payment date must be editable when marking paid. This applies to single-entry and batch-entry screens, mobile and web.

When changing payment status on mobile, update the local row and dirty flag in one transaction. On web, update Supabase directly. Realtime propagates the change to other devices.

---

## 10. Dashboard

Dashboard reads local Drift streams on mobile and Supabase-backed streams on web.

### Money cards

- Outstanding receivables.
- Pending remittance.
- This week's revenue.
- Last week's revenue and trend.
- This month's estimated profit; display “—” if cost data is unavailable.

### Customer cards

- Most loyal by order count.
- Top spenders by amount.
- Top unpaid balances.
- Customer of the Month.
- At-risk customers with no order in 30+ days.

### Product cards

- Best-seller by units.
- Best-seller by revenue.
- Unsold/overproduction watchlist.
- Suggested next bake based on high sales and low unsold rate.

### Operations

- Batches awaiting remittance.
- Recent payments.
- Recent batches.
- Active batches with remaining quantity.
- Sync/connection status.

### Trend

- Eight-week revenue bar chart.
- Optional monthly filter.

### Quick actions

- Add Batch.
- Batch Add Transactions.
- Log Single Transaction.
- Export Backup.

Implement dashboard calculations as shared Dart analytics functions over repository-provided lists where practical. If a list becomes too large later, move a specific aggregation to a Supabase RPC without changing the screen interface.

---

## 11. Screens and Responsive UI

### Screens

- Home dashboard.
- Batches list/create/edit/detail.
- Batch Add Transactions.
- Single Sale.
- Customers/search/ledger.
- Remittance.
- Settings.
- Import report.
- Sync diagnostics.
- Lock screen.

### Responsive shell

Phone uses bottom NavigationBar. Tablet and web use NavigationRail and optional two-pane list/detail layouts at width ≥700px.

### Mobile-only behavior

- Call/SMS buttons are shown only on Android using `url_launcher`.
- Biometric unlock is offered only on Android using `local_auth`; web uses PIN only.
- Image picker uses camera/gallery on Android and file selection on web.

---

## 12. Gap Improvements and Safety Features

### Profit tracking

Optional batch unit cost, live profit preview, monthly profit card, and later product-level profit reports.

### Locked batches

Remitted batches lock metadata while leaving payment collection editable. Unlock and un-remit require separate confirmations.

### Customer follow-up

Optional phone field; mobile call/SMS reminder based on current unpaid balance.

### App lock

Optional PIN on mobile/web, biometric enhancement on mobile. Store a SHA-256 hash locally only. Never sync lock settings.

### Backup

Export a JSON snapshot containing products, customers, batches, and sales. Mobile share sheet can save it to Google Drive; web downloads/shares it. This is a second safety net, not the primary sync mechanism.

### Product photos

Upload to Supabase Storage and store `image_url`; all devices show the same photo.

### Fun UX

Warm bakery theme, custom icon, friendly empty states, Customer of Month, sales streak, meaningful confetti, and optional rule-based baking suggestion.

### Deferred

Partial remittance. If required later, add `remittance_payments(batch_id, amount, date)`.

---

## 13. Spreadsheet Migration During Development

Do not create a live two-way Google Sheets integration. Keep AppSheet/Google Sheets active while development continues and use a re-runnable import.

### Workflow

1. Export the latest XLSX.
2. On mobile, open Settings → Import Latest Spreadsheet.
3. Parse only valid populated rows.
4. Import products and customers first.
5. Import batches using `tblRemittance.id → legacy_id`.
6. Import sales using `tblTransactions.id → legacy_id`.
7. Resolve foreign keys by product/customer/batch mapping.
8. Default legacy quantity to 1 unless safely inferred.
9. Classify `Unsold` and `Dante` rows.
10. Validate and show an import report.
11. Write to Drift with dirty flags.
12. Sync to Supabase.

### Idempotency

- Batches/sales upsert by legacy ID.
- Products/customers upsert by normalized natural key, but preserve original display name.
- Same file imported twice must create no duplicates or changes.
- If the source row changed, update the existing local row and mark it dirty.
- Never overwrite newer local app edits without showing a conflict/review decision.

### Import report flags

- Blank rows skipped.
- Missing IDs.
- Unknown product/customer/batch references.
- Count/price/total mismatch.
- Batch allocated quantity mismatch.
- Suspicious count/price inversion.
- Duplicate customer names.
- Duplicate legacy IDs.
- Invalid dates or amounts.
- Pseudo-customer classifications.

Keep `legacy_id` and importer code until final cutover and reconciliation. Then remove them only after a backup.

---

## 14. Dependencies

Use current compatible versions when creating the project; these are the intended packages:

```yaml
dependencies:
  drift: ^2.32.0
  drift_flutter: ^0.2.5
  path_provider: ^2.1.0
  path: ^1.9.0
  supabase_flutter: ^2.15.2
  connectivity_plus: ^6.0.0
  provider: ^6.1.0
  intl: ^0.19.0
  fl_chart: ^0.69.0
  uuid: ^4.4.0
  confetti: ^0.7.0
  local_auth: ^3.0.1
  image_picker: ^1.1.0
  url_launcher: ^6.3.0
  share_plus: ^11.1.0
  crypto: ^3.0.5

dev_dependencies:
  build_runner: ^2.4.0
  drift_dev: ^2.32.0
```

The web build must not instantiate Drift or require SQLite WASM files.

---

## 15. Netlify Deployment

Selected host: Netlify. Firebase Hosting and Cloudflare Pages remain valid alternatives, but changing static hosting does not change the app architecture.

For a small app, the simplest deployment is:

```bash
flutter build web --release
```

Upload the generated `build/web` directory to Netlify. Later, configure Git-connected deployment if frequent updates make manual upload inconvenient. No special WASM or COOP/COEP headers are needed because web uses Supabase directly and has no local browser database.

---

## 16. Build Order

1. Create Flutter project with Android and Web targets.
2. Add dependencies and establish environment configuration using `--dart-define`.
3. Define Drift tables and migrations for mobile.
4. Define `BakeryRepository` interface.
5. Implement LocalRepository and local CRUD.
6. Build responsive navigation shell.
7. Build Products, Customers, Batches, Single Sale, and Remittance screens locally.
8. Build Batch Add Transactions with quantity, duplicate warning, over-allocation warning, payment defaults, and atomic save.
9. Implement automatic `date_paid` behavior.
10. Implement locked batches and optional profit tracking.
11. Build dashboard analytics and widgets.
12. Create Supabase project, run schema/RLS/Storage/Realtime migrations, and create the single user account.
13. Implement authenticated Supabase client.
14. Implement mobile SyncService with push, pull, Realtime, retry, conflict handling, and diagnostics.
15. Implement RemoteRepository for web with direct Supabase CRUD and Realtime streams.
16. Implement product photo uploads to Supabase Storage.
17. Implement re-runnable XLSX importer and import report.
18. Test offline mobile entry → reconnect → Supabase → other mobile/web device.
19. Test simultaneous editing, payment-date changes, duplicate detection, over-allocation, locked batches, import reruns, RLS, and Storage policies.
20. Add app lock, backup export, mobile follow-up actions, and fun polish.
21. Build and deploy Web to Netlify.

---

## 17. Acceptance Criteria

The app is ready when:

- Phone and tablet can create/read/edit data offline.
- Mobile changes sync to Supabase after reconnecting.
- Web reads/writes Supabase directly.
- Changes from any device appear on other online devices through Realtime.
- Every sale stores batch ID, sale date, quantity, amount, payment state, and payment date.
- Mark Paid sets `date_paid`; Mark Unpaid clears it.
- Batch Add Transactions creates multiple customer rows atomically.
- Product is derived from the selected batch.
- Duplicate and over-allocation warnings work.
- Dashboard identifies loyal customers, top spenders, unpaid balances, best sellers, profit status, and trends.
- Remitted batches are protected from accidental metadata edits.
- Spreadsheet import is repeatable without duplicates.
- Import issues are visible instead of silently corrected.
- RLS prevents unauthorized data access.
- Product photos display across phone, tablet, and web.
- Backups can be exported.
- The web app deploys and runs from Netlify.
