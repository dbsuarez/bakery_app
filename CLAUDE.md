# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter bakery order & remittance tracker (product name "My Bakery"), replacing a Google Sheets/AppSheet workflow. Targets Android and Web, both built from the same codebase and both talking directly to Supabase (Postgres + Auth + Realtime + Storage) — there is no local database or offline mode.

## Commands

Run everything from the repo root (`d:\Development\bakery_app`).

```bash
flutter pub get                          # install/update dependencies
flutter analyze                          # static analysis — must be clean before considering a change done
flutter test                             # run tests (test/widget_test.dart)
flutter test test/widget_test.dart       # run a single test file

# Local dev run (needs Supabase credentials, see below)
flutter run --dart-define-from-file=dart_define.json

# Release builds (always pass the dart-define file — the app shows a
# "Missing Supabase configuration" screen without it)
flutter build apk --release --dart-define-from-file=dart_define.json
flutter build web --dart-define-from-file=dart_define.json
```

Supabase credentials live in `dart_define.json` (gitignored) at the repo root:
```json
{ "SUPABASE_URL": "https://xxx.supabase.co", "SUPABASE_ANON_KEY": "sb_publishable_..." }
```
Read via `String.fromEnvironment` in `lib/config.dart`. Without it, `SupabaseConfig.isConfigured` is false and `main.dart` shows a static error screen instead of the app.

An optional `--dart-define=BUILD_TIME="$(date '+%Y-%m-%d %H:%M')"` stamps a build timestamp shown in Settings (`lib/build_info.dart`) — useful for confirming a freshly-installed build during iterative development.

### Deploying

- **Android**: `flutter build apk --release ...` then `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
- **Web**: `flutter build web --dart-define-from-file=dart_define.json` then deploy `build/web/` to Netlify (site id in `.netlify/state.json`) via `npx netlify-cli deploy --prod --dir=build/web --site=<siteId>`.
  - **Known flutter build web flakiness**: a `flutter build web` invocation has been observed to report success while silently omitting `assets/`, `FontManifest.json`, and the app icons (all Material icons then render as tofu boxes on the deployed site). Always verify after building: `find build/web -iname "*.otf"` should find `assets/fonts/MaterialIcons-Regular.otf`, and the file count should be ~30+. If missing, `rm -rf build/web` and rebuild from a clean state before deploying.

## Architecture

### No local database — everything is Supabase-direct

Both Android and Web use `RemoteRepository` (`lib/repository/remote_repository.dart`), which talks to Supabase's REST/Realtime API directly. There is no Drift/SQLite, no sync layer, and no offline support — the app requires an internet connection. (An earlier local-first architecture with a Drift DB + background sync service was deliberately removed after persistent, unfixable DNS-resolution failures on the Supabase auth-token-refresh call on one test device; see git history if resurrecting that approach is ever considered.)

Supabase primary keys are UUIDs, but the app's domain models and UI use `int` ids throughout (to keep screens simple). `RemoteRepository` bridges this with a private `_IdMapper`: it assigns a stable, session-local int to each UUID the first time it's seen, and maps back via `toUuid()`. This mapping is **not persisted** — it's rebuilt each app launch from whatever rows the live queries return.

### Repository pattern

`lib/repository/bakery_repository.dart` defines the abstract `BakeryRepository` interface (watch streams per table, create/update/mark-paid/mark-remitted methods). `RemoteRepository` is the sole implementation. `lib/app_state.dart`'s `AppState` (a `ChangeNotifier`) subscribes to the four `watchX()` streams and exposes synchronous `products`/`customers`/`batches`/`sales` lists plus `productById`/`customerById`/`batchById` lookups — this is what every screen actually reads via `context.watch<AppState>()`.

Providers are wired in `lib/main.dart`, declared **above** `MaterialApp` (not inside `home`) so that `Navigator.push`-ed routes — not just the initial screen — can see them via `context.read`/`context.watch`.

### Domain models vs. business rules

`lib/models/` (`Product`, `Customer`, `Batch`, `Sale`) are plain data classes matching the Supabase schema (`docs/supabase_bakery_database_setup.sql`). Business rules and derived numbers live in `lib/analytics/`:
- `batch_calculations.dart`: `remainingQuantity`/`allocatedQuantity` — a batch's remaining stock is `countProduced` minus **both** real `customer_sale` quantity and `internal_consumption` (freebies/samples) quantity, since both remove stock from availability even though only `customer_sale` counts as revenue.
- `customer_calculations.dart`: balances, order counts, at-risk detection.
- `dashboard_analytics.dart`: `computeDashboard()` builds the full `DashboardData` for the dashboard screen. Personal batches (`Batch.isPersonal`) are excluded from every business-performance figure (revenue, profit, best-sellers, customer stats) but get their own parallel "personal" figures (`personalUnsoldValue`, `personalUnsoldWatchlist`, `personalActiveBatches`) — don't merge these back together.

Key domain concepts to know before touching business logic:
- **`sale_type`**: `customer_sale` | `unsold` | `internal_consumption`. Classification is by the transaction's amount (₱0 → `internal_consumption`), never by which customer it's attached to — real customers can also receive freebies.
- **Personal batches**: `Batch.isPersonal` skips the remittance flow entirely (never shown in Remittance screen, never blocks on "must remit before X").
- **Locked batches**: `Batch.locked` (set when `remitted = true`) blocks edits to batch metadata and blocks new `customer_sale` rows, enforced in `RemoteRepository.addSingleSale`/`updateBatch`. New `internal_consumption` entries are explicitly allowed on locked batches (zero revenue impact, just inventory bookkeeping) — see the lock check in `addSingleSale`.
- **`legacy_id`** (nullable int, unique per user) on `batches`/`sales`: exists solely so the XLSX importer (`lib/import/import_service.dart`) and JSON restore (`lib/import/backup_restore_service.dart`) can upsert idempotently against the old spreadsheet's row ids instead of duplicating on re-run. Not used anywhere else.

### Import / Backup / Restore

Three independent, repository-bypassing services that talk to `SupabaseClient` directly (not through `BakeryRepository`), because they need bulk upsert-by-natural-key logic the repository interface doesn't expose:
- `lib/import/import_service.dart` — parses the legacy AR Spreadsheet (`lib/import/xlsx_parser.dart`) and upserts by `legacy_id`. Safe to re-run.
- `lib/backup/backup_service.dart` — exports all data to JSON via `share_plus` (works cross-platform, including a web download fallback).
- `lib/import/backup_restore_service.dart` — restores that JSON back in, matching by `remote_id` (Supabase UUID) first, then natural key (title/name) or `legacy_id`. Safe to re-run.

### Supabase schema notes (`docs/supabase_bakery_database_setup.sql`)

- RLS policies alone are not sufficient — Postgres also needs base-table `GRANT`s to the `authenticated` role, or every query is rejected before RLS even runs (42501). Both are in the setup script.
- The Dart Supabase client's `.order()` defaults to **descending** (`ascending: false`), the opposite of SQL/JS convention — always pass `ascending:` explicitly in `RemoteRepository`'s `watchX()` queries or ordering silently inverts.
- The script includes standalone `alter table ... add column if not exists ...` statements at the bottom for evolving an already-created database (e.g. `is_personal`, `legacy_id`) without re-running the whole script — extend this pattern for future schema changes rather than editing the `create table` blocks (which only apply to fresh projects).

### UI structure

`lib/ui/shell/app_shell.dart` is a responsive shell: `NavigationRail` at width ≥700px, bottom `NavigationBar` below that. Five tabs: Dashboard, Batches, Customers, Remittance, Settings. `lib/auth/auth_gate.dart` gates the shell behind Supabase auth state, then (non-web only) behind `AppLockGate` (`lib/security/`) if the user has set an app PIN — PIN/biometric state is stored in `shared_preferences`, per-device, never synced.

Dates are formatted consistently via `lib/utils/app_date_format.dart` (`yyyy-MM-dd`) — use `appDateFormat`/`appDateTimeFormat` rather than ad-hoc `DateFormat` calls.
