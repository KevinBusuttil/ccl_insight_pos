# Local Multi-Shop Manual Test Report

Date: 2026-09-29

## Environment

- Flutter client: Android debug build from the current `neuradix-pos` working tree
- Tablet register: `emulator-5554`, Shop A
- Phone register: `emulator-5556`, Shop B
- Metadata backend: deployed Neuradix test service
- Relay: deployed stateless WebSocket service
- Test business: synthetic certification business `NBIZ-00004`
- Data policy: synthetic customers, items, and sales only; no credentials are recorded

## Manual Matrix

| Scenario | Expected | Actual | Result |
| --- | --- | --- | --- |
| Register business | Business and first shop are created atomically | Business and Shop A were created from the Flutter registration flow | Pass |
| Add shop | Owner can add another shop without backend seeding | Shop B was created in Shop Management | Pass |
| Pair register | New register selects Shop B before pairing | Phone selected Shop B, produced a pairing request, and was approved by Shop A | Pass |
| Local catalogs | Each shop keeps only its own items and stock | Shop A retained four A items; Shop B retained four B items | Pass |
| Both offline | Each shop can create three customers and three sales | Local records remained usable and encrypted outboxes survived restart | Pass |
| Offline recovery | Queued events transfer after both registers reconnect | Both registers converged to six sales and six customers | Pass |
| Both online | Three more sales per shop synchronize without duplicates | Both registers converged to 12 sales | Pass |
| Mixed connectivity | Both shops sell while Shop A is offline and Shop B is online | Shop A queued three sales; Shop B retained three unacknowledged sales | Pass |
| Restart under load | Pending events survive application restart | Shop B events remained pending after force-stop/restart | Pass |
| Final convergence | Each register sees 18 sales and six customers | Both registers reached 18 sales, six customers, and zero pending events | Pass |
| Sale snapshots | Cross-shop sale lines appear in history without creating inventory | Item descriptions, barcode, quantity, and rate travelled with sales only | Pass |
| Duplicate replay | Replayed envelopes do not duplicate data | Duplicate frame was identified and ignored | Pass |
| Reverse direction | A smaller reverse-direction customer update converges | Independent Shop A and Shop B edits converged | Pass |
| Server boundary | Local Multi-Shop creates no hosted operational rows | Product, Customer, Sale, and Sale Item counts were all zero | Pass |

## Final Device Assertions

- Shop A: 4 items, 6 customers, 18 sales, 9 locally-originated sales, 0 pending events.
- Shop B: 4 items, 6 customers, 18 sales, 9 locally-originated sales, 0 pending events.
- Catalog intersection: none.
- Finalized-sale ID sets: identical.
- Customer ID sets: identical.

## Recovery And Safety Observations

- Drafts and parked carts remained local and were not emitted as sync events.
- A pending event was removed only after a trusted peer durably applied and acknowledged it.
- The relay retained no mailbox or operational payload database.
- Devices must overlap online to exchange queued events.
- If every synchronized device is lost, Local Multi-Shop operational data cannot be recovered from Neuradix Cloud.

## Sign-Off

No blocker, critical, high, or unresolved medium defects remain in the tested scope. Production rollout still requires HTTPS/WSS, an operational backup policy, and a decision on anti-entropy/snapshot recovery.
