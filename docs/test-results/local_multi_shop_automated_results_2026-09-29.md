# Local Multi-Shop Automated Verification

Date: 2026-09-29

## Single Trigger

The complete project regression is launched from:

```bash
/Users/trek-matrix/Work/Kevins_work/neuradix-bench/run_all_tests.sh
```

The deployed backend and two-emulator suite are added with:

```bash
RUN_SERVER_E2E=1 /Users/trek-matrix/Work/Kevins_work/neuradix-bench/run_all_tests.sh
```

## Deterministic Coverage

- Backend unit tests cover atomic first-shop registration, owner-only shop creation, duplicate shop codes, enrollment expiration, trusted-device approval, token shop claims, forged-shop rejection, event allowlists, same-shop inventory routing, and business-wide customer/sale routing.
- Flutter repository tests cover encrypted outbox durability, trusted peer acknowledgements, same-shop inventory, cross-shop inventory rejection, customer conflict handling, immutable sale snapshots, duplicate replay, and parked-sale rejection.
- Flutter widget tests cover Local Multi-Shop registration fields, Shop Management, shop selection before enrollment, safe reassignment guards, diagnostics, compact phone layout, and responsive tablet layout.
- The deterministic two-register acceptance test covers four isolated items per shop, six shared customers, 18 shared finalized sales, offline/online/mixed connectivity, restart durability, duplicate frames, reverse-direction edits, and cross-business defense.
- Python ADB tooling tests cover accessibility geometry, text entry, foreground detection, IME visibility, resumable completion, result consistency, and SQL audit parsing.

## Live Server And Emulator Result

The resumable ADB harness completed against the deployed metadata backend and stateless relay. The authoritative machine-readable artifacts are:

- `docs/test-results/screenshots/local_multi_shop_server_e2e_result.json`
- `docs/test-results/screenshots/local_multi_shop_server_storage_audit.json`

Verified result:

- Final certification run: `130717` for synthetic business `NBIZ-00004`.
- Shop A: 4 items, 6 customers, 18 sales, 0 pending.
- Shop B: 4 items, 6 customers, 18 sales, 0 pending.
- Hosted Product rows: 0.
- Hosted Customer rows: 0.
- Hosted Sale rows: 0.
- Hosted Sale Item rows: 0.

## Final Regression Counts

- Neuradix backend: 61 tests passed.
- Cassar POS backend: 11 tests passed.
- Cassar operations backend: 56 tests passed.
- Customer portal backend: 13 tests passed.
- Operations tooling: 11 tests passed.
- Neuradix POS: static analysis clean, 92 Flutter tests passed, and 21 Python tooling/PDF tests passed.
- Customer portal: static analysis clean and 24 tests passed.
- Cassar logistics frontend: static analysis clean and 28 tests passed.
- Unified bench migration, app-stack smoke, Insight planning handoff, full delivery, partial delivery, and failed-delivery reconciliation passed.

## Release Gates

- Dart formatting: required.
- Flutter static analysis: required.
- All Flutter unit, repository, and widget tests: required.
- Backend and all related Cassar app suites: required.
- Bench migration/smoke and Insight transport integration: required.
- Deployed two-emulator matrix and raw SQL storage audit: required when `RUN_SERVER_E2E=1`.
- PDF render, text extraction, metadata, and required-heading checks: required for documentation release.
