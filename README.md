# My Bakery

A Flutter order & remittance tracker for a home bakery business, replacing a
Google Sheets/AppSheet workflow. Runs on Android and Web from the same
codebase, talking directly to Supabase (Postgres + Auth + Realtime + Storage)
— there's no local database or offline mode.

## Features

- **Batches & transactions** — track what's produced, sold, given away
  (internal consumption/samples), or left unsold, per batch
- **Customers** — per-customer ledger, balances, loyalty/spending stats,
  at-risk detection, archive (hide without deleting)
- **Remittance** — lock a batch's numbers once its proceeds are handed over,
  with totals for awaiting/remitted batches
- **Personal batches** — track baking for your own use separately from the
  business, with its own dashboard figures that never mix into business
  totals
- **Dashboard** — money/customer/product/operations cards, a daily/weekly/
  monthly revenue trend chart, an All/Baking/Personal filter
- **Products** — rename products and attach a photo (shown throughout the
  app: batches, dropdowns, ledgers)
- **Reports** — export a sales CSV for any date range, or a PDF statement of
  a customer's unpaid balance, ready to share straight to Messenger/etc.
- **Backup & restore** — full JSON export/import, plus one-time import from
  the legacy spreadsheet
- **App Lock** — optional PIN + biometric lock (mobile only)
- **Theming** — light/dark/system, a few color presets, or pick a custom
  color

See [CLAUDE.md](CLAUDE.md) for architecture notes, business rules, and
Supabase schema details.

## Setup

Supabase credentials go in a gitignored `dart_define.json` at the repo root:

```json
{
  "SUPABASE_URL": "https://xxx.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_...",
  "CUSTOMER_PORTAL_URL": "https://your-site.netlify.app/"
}
```

Run the SQL in `docs/supabase_bakery_database_setup.sql` against your
Supabase project first (tables, RLS, and the `product-photos` storage
bucket).

## Commands

```bash
flutter pub get
flutter analyze                          # must be clean before considering a change done
flutter test

flutter run --dart-define-from-file=dart_define.json

flutter build apk --release --dart-define-from-file=dart_define.json
flutter build web --dart-define-from-file=dart_define.json
```

### Deploying

- **Android**: `flutter build apk --release ...` then
  `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
- **Web**: `flutter build web --dart-define-from-file=dart_define.json` then
  `npx netlify-cli deploy --prod --dir=build/web --site=<siteId>`. Verify
  `assets/fonts/MaterialIcons-Regular.otf` exists in the build output before
  deploying — `flutter build web` has occasionally omitted assets silently.
