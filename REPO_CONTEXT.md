## Reference tablet layout (2026-10-10)
- CatalogProductGrid replaces category shelves in Order: adaptive up-to-three columns, name-first cards, fixed full-width search, real stock/UOM/rates. Product preview preserved.
- Sidebar narrowed to 90 while retaining backend menu accent colors. Customer controls/account details moved above Current order in right pane; cart quantity row below names; empty parked panel hidden.
- Regression test in test/widget_test.dart; run complete single trigger before release.

## Tablet category shelves (2026-10-09)
- Order controls remain outside scrolling catalog. Compact workspace no longer scrolls its fixed-height parent. Search expands beside compact customer/account controls.
- CatalogCategoryShelf: horizontal linked two-row tablet grids, one row on smaller screens; search uses wrapped result cards. Card long press or Product details opens showCatalogItemPreview without adding.
- showHistoryOrderDetails uses saved prices/UOM/amount/comments and retained JSON metadata; no recalculation. Plan & Sync shows customer count instead of redundant list. Regression tests in test/widget_test.dart.

## Category / brand / theme UI (2026-10-08)
- `CategoryMultiSelect` in app shell: collapsed searchable checkbox list, removable selected tags; `PosHomeController.setCategories` filters union of categories, intersected with product search. Empty selection means all.
- `PosShellHeader`: compact client brand plus Powered by Neuradix; brand_name comes from backend settings.
- `PosThemePalette.menu*` and `NeuradixTheme.menuAccent`: backend menu_customer/sync/history/profile color fields, serialized in bootstrap/cache. Main palette retains teal. Admin controls Neuradix POS Settings.

# Neuradix POS Frontend Context

This repository holds the new Flutter `neuradix_pos` client.

## Dedicated Cassar UAT pricing plan — 2026-10-07
- Plan: `/Users/trek-matrix/Documents/ChatGPT/Marsovin-ERP-test/ops/POS_TRADE_AGREEMENT_PLAN.md`; target restored UAT `http://209.38.46.169` on dedicated_backend mode, with current administrator IP allowlist.
- `start_macos.sh` accepts NEURADIX_DEFAULT_URL; stored instance URLs/cache must also be switched and isolated by site.
- `pos_home_controller.dart`: customer selection loads Insight-backed catalog; customer/quantity/UOM/cart/date server quotes and saved ERP price parity are implemented. `isCustomerLoading` starts before cache/network work and resets in finally.
- `CompactOrderWorkspace` in `lib/src/app/neuradix_pos_app.dart`: persistent View cart button and live bottom sheet for compact emulator/mobile screens; phone widths below 700 use a navigation dropdown and compact `PosShellHeader`; `PosLoadingIndicator` in the shared shell covers Order and Plan & Sync requests. Widget/controller regressions in `test/widget_test.dart` and `test/src/features/pos/pos_home_controller_test.dart`.
- Trade-agreement rules remain server-owned through Neuradix and the configured ERPNext/Insight lifecycle. Offline stale/context-mismatched prices require explicit provisional-order and re-quote handling.

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
- Platform-aware connection error formatting: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/bootstrap/connection_error_formatter.dart`
- Hosted POS search, image, payload, and cart-state helpers: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/hosted/hosted_pos_support.dart`
- Hosted SQLite cache, business-switch guard, and cloud-history replacement: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/data/local/hosted_local_repository.dart`
- Runtime bench URL normalization helper: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/bootstrap/runtime_bench_url.dart`
- Order and sync feature: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/orders`
- Local multi-shop coordination, crypto, keys, HLC, and bootstrap: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/local_sync`
- Local multi-shop SQLite outbox/inbox and merge repository: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/data/local/local_sync_repository.dart`
- POS API and state layer: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/pos`
- Offline image sync service: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/pos/catalog_image_sync_service.dart`
- Catalog image rendering helpers: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/lib/src/features/pos/catalog_image_provider.dart`
- POS controller coverage: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/test/src/features/pos`
- Tests: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/test`
- Repo test runner: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/run_tests.sh`
- Approved local multi-shop sync plan: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/plans/neuradix_local_multi_shop_sync_plan.md`
- Editable client brochure source: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/brochures/neuradix_pos_client_brochure.md`
- Generated client brochure PDF: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/output/pdf/Neuradix_POS_Client_Brochure.pdf`
- Local Multi-Shop user guide source: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/guides/neuradix_pos_local_multi_shop_user_guide.md`
- Local Multi-Shop technical architecture source: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/architecture/neuradix_pos_technical_architecture.md`
- Current Local Multi-Shop architecture status: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/architecture/local_multi_shop_architecture_status.md`
- Manual certification report: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/test-results/local_multi_shop_manual_test_report_2026-09-29.md`
- Automated certification report: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/test-results/local_multi_shop_automated_results_2026-09-29.md`
- Certification bug log: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/test-results/local_multi_shop_bug_log_2026-09-29.md`
- Machine-readable server E2E result: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/test-results/screenshots/local_multi_shop_server_e2e_result.json`
- Machine-readable raw-SQL storage audit: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/test-results/screenshots/local_multi_shop_server_storage_audit.json`
- Sanitized certification screenshots: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/docs/test-results/screenshots/local_multi_shop_2026-09-29`
- Reproducible PDF generator and validator: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/tool/docs`
- Generated Local Multi-Shop user guide PDF: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/output/pdf/Neuradix_POS_Local_Multi_Shop_User_Guide.pdf`
- Generated Local Multi-Shop technical PDF: `/Users/trek-matrix/Work/Kevins_work/neuradix-pos/output/pdf/Neuradix_POS_Technical_Architecture.pdf`
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
- Android release networking is declared in `android/app/src/main/AndroidManifest.xml`; cleartext transport remains explicitly enabled while the shared certification backend is served from `http://167.172.37.224:8089`, and should be disabled when production moves to HTTPS/WSS
- Existing app installs are upgraded in place by the local SQLite migration path; do not assume a clean DB on developer machines
- The fifth left-rail tab is `Plan & Sync`, which owns day selection, rep visit plans, and offline customer-price/image sync
- Offline ordering is strict for customer pricing: if a customer's day pack has not been synced, the app must block offline ordering for that customer
- Hosted Neuradix shops now have three plan states: `free_local` for device-local operations after day-one registration, `free_cloud` for capped shared-bench sync, and `paid_cloud` for unrestricted hosted sync
- The hosted auth screen registers either `free_local` or `free_cloud`; upgrades move lower tiers into `paid_cloud` with local data import
- Backend validation errors from hosted auth, including password-policy failures, are unwrapped from Frappe `_server_messages` and shown as readable inline text instead of raw `ValidationError`
- A hosted sale clears the cart once it has been persisted locally, including when cloud submission fails and the sale is safely queued for replay; local persistence failures preserve the cart for retry
- Shared Cloud synchronization is backend-mediated and pull-based: another register receives products, customers, and submitted sales when it logs in or runs Refresh; there is no device-to-device push in this mode
- Shared Cloud refresh replaces submitted history for the authenticated business while retaining queued local sales; changing businesses clears synced hosted caches and is blocked while unsynced or local-only sales remain
- Compact hosted phone layouts scroll the full shell body, and compact Sales uses one vertical flow so inventory, customer selection, cart, and Record Sale remain reachable on short screens
- Network error guidance is platform-aware: macOS sandbox entitlement guidance must never be shown for Android or other platforms
- Local Multi-Shop is an opt-in `free_local + local_multi_shop` topology exposed only when the hosted backend enables `feature_local_multi_shop_sync`; it does not write products, customers, or sales to hosted operational DocTypes
- Local Multi-Shop foundation is implemented through schema version 6: trusted metadata bootstrap, platform-secure Ed25519/X25519/AES keys, signed encrypted envelopes, transactional customer/finalized-sale outbox writes, HLC customer merges, immutable replicated sale snapshots, acknowledgement tables, and conflict records
- Item masters, prices, images, barcodes, and stock replicate only between registers assigned to the same shop; customers and finalized sales replicate business-wide, while drafts and parked carts never replicate
- The hosted shell widget state is keyed by `businessId:shopId`; server-side register reassignment remounts the shell after metadata bootstrap so stale inventory or cart state from the previous shop cannot remain visible
- The live WebSocket relay worker and manual text-code trusted-device pairing flow are implemented and covered by unit tests. QR camera pairing, snapshot/anti-entropy catch-up, operator PINs, and SQLCipher database encryption remain release-blocking follow-up phases
- Relay reliability uses application ping/pong heartbeats, stale-socket replacement, connection-specific callbacks, forced reconnection from Refresh, and automatic reconnection when the app resumes. Refresh reports when no other trusted register is online instead of claiming convergence; the stateless relay still requires devices to overlap online.
- The current release-signoff evidence is the 18-sale two-emulator matrix in `docs/test-results/local_multi_shop_manual_test_report_2026-09-29.md`, `docs/test-results/local_multi_shop_automated_results_2026-09-29.md`, and the associated machine-readable result/audit files. Older two-emulator and server reports remain historical evidence only.

## Dedicated CassarCamilleri UAT build
- Build define `NEURADIX_DEDICATED_URL=http://209.38.46.169` fixes the bench and uses separate `neuradix_ccl_uat.db`. Android adds `.ccl_uat` application ID and UAT label; never embed a password.
- `lib/src/features/pos/neuradix_api_client.dart`: current-session browser CSRF and server cart quotes.
- `lib/src/features/pos/pos_home_controller.dart`: `server_cart_quotes` feature; re-quote add/quantity/customer/parked restore, ignore stale async responses, accepted quote submission with server date, preserve failed cart and stable retry ID. Agreement order submission requires online pricing.
- `lib/src/features/pos/pos_models.dart`: default UOM and explicit pricing availability survive cache; cart sends actual UOM.
- `lib/src/data/local/pos_cache_repository.dart`: customer ID/name/mobile search.
- `test/src/features/pos/{pos_home_controller,neuradix_api_client}_test.dart` and cache tests cover dedicated integration and regressions. Use ./run_tests.sh; format with its selected Dart version.
- UAT web path `/pos/`; macOS build requires user acceptance of current Xcode license.
