# Local Multi-Shop Server E2E Result

Date: 2026-09-29

> Historical smoke certification. The later 18-sale release matrix for business `NBIZ-00004`, including the mandatory raw-SQL audit, supersedes this report. Use `local_multi_shop_manual_test_report_2026-09-29.md` and `local_multi_shop_automated_results_2026-09-29.md` for release sign-off.

## Scope

This test exercised a real `free_local + local_multi_shop` business through two Android emulators against the deployed Neuradix metadata backend and stateless WebSocket relay. It covered registration, trusted-device pairing, same-shop replication, peer-offline replay, cross-shop isolation, shared records, rejected hosted persistence, and server storage auditing.

## Environment

- Tablet register: `emulator-5554`
- Phone register: `emulator-5556`
- Metadata backend: `http://167.172.37.224:8089`
- Stateless relay: `ws://167.172.37.224:8787`
- Deployed Neuradix commit: `e9f69fe10fd3c67411e7a1693024ed32373f9052`
- Test business: `ServerE2EABP` (`NBIZ-00003`)
- Main shop: `ServerE2EABP`
- Branch shop: `Server Branch Shop`
- Both registers reached `Sync: Live Relay`

## Registration And Pairing

1. Registered the metadata-only business from the Flutter application.
2. Registered the tablet as the first trusted device.
3. Logged in on the phone and received the expected pairing-required state.
4. Approved the phone from the trusted tablet with the text pairing code.
5. Completed enrollment on the phone and confirmed both devices connected to the relay.

Result: PASS.

## Same-Shop Replication

1. Created `ServerCoffee` (`SRV-COFFEE`, barcode `8901234567890`) on the tablet.
2. Observed the item automatically on the phone while both registers belonged to the main shop.
3. Created `ServerSharedCustomer` and observed it on the phone.
4. Recorded a `EUR 7.50` sale on the phone.
5. Observed the replicated sale in tablet history and opened its item-level details.

Result: PASS.

## Offline-Peer Replay

1. Stopped the tablet application.
2. Created `OfflineRelayCustomer` on the phone.
3. Confirmed the phone retained the outgoing event without peer acknowledgement.
4. Relaunched the tablet and observed the customer after it reconnected.
5. Confirmed the phone event advanced to `acknowledged` only after the tablet durably applied it.

Result: PASS. This proves source-device outbox replay while the source remains available; it does not provide a durable relay mailbox.

## Cross-Shop Isolation

1. Created `Server Branch Shop` and reassigned the phone through the authenticated metadata APIs.
2. Restarted the phone and confirmed the old shop catalog was cleared.
3. Created `BranchTea` (`SRV-TEA`, barcode `8901234567891`) on the branch phone.
4. Confirmed the phone contained only `BranchTea` and the tablet contained only `ServerCoffee`.
5. Confirmed the tablet stored the cross-shop item event as `ignored_shop_scope`.
6. Created `BranchSharedCustomer` on the phone and observed it on the tablet.
7. Recorded a `EUR 5.25` branch sale and observed the immutable sale snapshot in tablet history.
8. Opened the tablet sale dialog and confirmed `BranchTea`, quantity `1`, and `EUR 5.25`, without adding `BranchTea` to the tablet catalog.

Result: PASS.

## Regression Found And Fixed

The first shop reassignment exposed a frontend lifecycle bug: SQLite correctly cleared the old shop inventory, but the already-mounted Sales screen retained its in-memory list. The hosted shell is now keyed by `businessId:shopId`, so metadata reconciliation that changes either scope remounts the shell and reloads the correct local cache. A regression test verifies that business and shop changes produce distinct state scopes.

Result after rebuilding and reinstalling: PASS. The branch register immediately showed an empty catalog while the main register retained `ServerCoffee`.

## Server Storage Audit

For `NBIZ-00003`, the deployed backend contained:

- Shops: 2
- Trusted devices: 2, one assigned to each shop
- Device enrollments: 1
- Opaque device key envelopes: 1
- `Neuradix Product`: 0
- `Neuradix Customer`: 0
- `Neuradix Sale`: 0
- `Neuradix Sale Item`: 0

An authenticated attempt to call the hosted inventory persistence endpoint returned `NeuradixValidationError`. A second SQL audit confirmed all four operational row counts remained zero. The relay has no payload database; identity, subscription, shop/device metadata, public keys, and opaque key envelopes remain server-side.

## Automated Verification

- Deployed Neuradix backend: 55 tests passed.
- Full platform trigger: passed.
- Backend suites: Neuradix 55, Cassar POS backend 11, Cassar operations backend 56, customer portal backend 13.
- Operations tooling: 11 tests passed.
- Neuradix POS: analysis clean and 81 tests passed.
- Customer portal: analysis clean and 24 tests passed.
- Cassar logistics frontend: analysis clean and 28 tests passed.
- Unified Cassar bench migration and app-stack smoke: passed.
- Insight route planning, Pick List handoff, full delivery, partial delivery, and failed delivery reconciliation: passed.
- Android log audit: no fatal or unhandled Flutter exceptions on either emulator.

## Remaining Production Gaps

- The deployed test endpoint currently uses plaintext HTTP and WebSocket; production requires HTTPS and WSS.
- Pairing uses a text code; QR camera pairing is not implemented.
- Devices must overlap online because there is no durable cloud mailbox.
- Snapshot and anti-entropy recovery are not implemented.
- Operator PIN separation and SQLCipher database encryption remain pending.
- Metadata-only recovery cannot restore operational data if every synchronized device is lost.
