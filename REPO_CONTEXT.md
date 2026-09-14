# Neuradix POS Frontend Context

This repository holds the new Flutter `neuradix_pos` client.

## Backend Boundary
- This is one of three independent Flutter clients served by the single Cassar backend site in `/Users/trek-matrix/Work/Kevins_work/neuradix-bench`.
- It must point to the same site URL as CC Connect and Neuradix Cassar Operations; it does not own or require another Frappe bench.
- POS calls `neuradix.api.v1.*` and `neuradix_cassarcamilleri.api.v1.*`. Any Insight-backed behavior is reached through those backend boundaries, never by calling Insight or AX from Flutter.

## First Places To Look
- App shell: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/app`
- Theme and visual system: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/theme`
- SQLite layer: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/data/local`
- SQLite schema and upgrade path: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/data/local/neuradix_database.dart`
- SQLite cache/query facade: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/data/local/pos_cache_repository.dart`
- Bootstrap feature: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/bootstrap`
- Runtime bench URL normalization helper: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/bootstrap/runtime_bench_url.dart`
- Order and sync feature: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/orders`
- POS API and state layer: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/pos`
- Offline image sync service: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/pos/catalog_image_sync_service.dart`
- Catalog image rendering helpers: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/pos/catalog_image_provider.dart`
- POS controller coverage: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/test/src/features/pos`
- Tests: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/test`
- Repo test runner: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/run_tests.sh`
- Web launcher: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/start_web.sh`
- macOS launcher: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/start_macos.sh`
- macOS entitlements: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/macos/Runner/DebugProfile.entitlements` and `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/macos/Runner/Release.entitlements`

## Frontend Direction
- New codebase only, no Hive carry-forward
- SQLite is the local source of truth for config, cached customers/catalog, parked orders, and sync queue
- Additional SQLite tables now hold visit plans, per-day customer price snapshots, customer policy snapshots, catalog image manifests, and sync cursors
- `client_order_id` is the stable idempotency key for offline replay
- `PosHomeController` owns launch replay, live customer-priced catalog swaps, day-scoped offline price packs, visit-plan editing, image sync, minimum-order note bypass, parked-order flow, and logout sync guards
- Tablet parity with the legacy CassarCamilleri POS comes before macOS/mobile adaptation
- The stored `instance_url` drives all backend calls and defaults to `http://neuradix-cassar.localhost:8008`
- Same-machine macOS development should use `http://neuradix-cassar.localhost:8008` or `http://127.0.0.1:8008`; use the LAN IP only from another device
- Android emulator builds rewrite `127.0.0.1`, `localhost`, and local `.localhost` Neuradix bench aliases to `10.0.2.2` at runtime so both dedicated and hosted benches are reachable without custom per-device setup
- Existing app installs are upgraded in place by the local SQLite migration path; do not assume a clean DB on developer machines
- The fifth left-rail tab is `Plan & Sync`, which owns day selection, rep visit plans, and offline customer-price/image sync
- Offline ordering is strict for customer pricing: if a customer's day pack has not been synced, the app must block offline ordering for that customer
- Hosted Neuradix shops now have three plan states: `free_local` for device-local operations after day-one registration, `free_cloud` for capped shared-bench sync, and `paid_cloud` for unrestricted hosted sync
- The hosted auth screen registers either `free_local` or `free_cloud`; upgrades move lower tiers into `paid_cloud` with local data import
- Backend validation errors from hosted auth, including password-policy failures, are unwrapped from Frappe `_server_messages` and shown as readable inline text instead of raw `ValidationError`
