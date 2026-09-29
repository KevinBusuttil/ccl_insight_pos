# Local Multi-Shop Two-Emulator E2E Result

Date: 2026-09-29

## Scope

This test exercised one `free_local + local_multi_shop` business through two Android emulators against the local Neuradix Cloud metadata bench and the stateless WebSocket relay. It covered both two registers in one shop and registers assigned to different shops.

## Environment

- Tablet register: `emulator-5554`
- Phone register: `emulator-5556`
- Metadata backend: `neuradix-cloud.localhost:8018`
- Stateless relay: port `8787`
- Backend feature response: `features.local_multi_shop_sync = true`
- Both registers reached `Sync: Live Relay`

## Same-Shop Result

1. Enrolled the phone from the already trusted tablet using the text pairing code.
2. Confirmed both devices were trusted and connected to the live relay.
3. Created `ABP Main Coffee` on the tablet and observed it on the phone while both devices belonged to the default shop.
4. Created `Multi Shop Customer` on the tablet and observed it on the phone.
5. Finalized a `EUR 7.50` sale on the phone and observed an immutable replicated history row on the tablet.

Result: PASS.

## Different-Shop Result

1. Created the `ABP Sliema` shop as metadata and assigned the phone register to it.
2. Restarted the phone and confirmed its old shop inventory cache was cleared while shared customers and finalized sales remained.
3. Created `Sliema Tea` on the phone. The phone stored it; the tablet retained only `ABP Main Coffee` and recorded the incoming item event as `ignored_shop_scope`.
4. Created `Sliema Customer` on the phone and observed it on the tablet.
5. Finalized a `EUR 5.25` sale on the phone and observed it in tablet history even though the Sliema item master did not enter the tablet inventory.

Result: PASS.

## Delayed Delivery Result

1. Stopped the tablet app while leaving the phone and stateless relay running.
2. Created `Delayed Sync Customer` on the phone.
3. Confirmed the phone retained the outgoing event as `sent` without an acknowledgement while the tablet was offline.
4. Relaunched the tablet and confirmed it returned to `Sync: Live Relay` and received the customer.
5. Confirmed the tablet durably marked the incoming event `applied` before the phone advanced its outbox event to `acknowledged`.

Result: PASS. This proves source-device outbox replay across a temporary peer disconnect; it does not imply a durable relay mailbox.

## Device Database Audit

Tablet/default shop:

- Inventory: `ABP Main Coffee` only
- Customers: `Multi Shop Customer`, `Sliema Customer`, `Delayed Sync Customer`
- Finalized sales: `EUR 7.50`, `EUR 5.25`
- Cross-shop `Sliema Tea` event status: `ignored_shop_scope`

Phone/ABP Sliema:

- Inventory: `Sliema Tea` only
- Customers: `Multi Shop Customer`, `Sliema Customer`, `Delayed Sync Customer`
- Finalized sales: `EUR 7.50`, `EUR 5.25`
- Outgoing item, customer, and sale events were acknowledged by the trusted peer

## Backend Storage Audit

For this test business, the shared backend contained:

- `Neuradix Product`: 0
- `Neuradix Customer`: 0
- `Neuradix Sale`: 0
- `Neuradix Sale Item`: 0
- Shops: 2
- Device rows: 3, including the original keyless hosted-login device metadata row
- Device enrollment rows: 1 completed and 1 expired historical request
- Active opaque device key envelopes: 1

The relay has no payload database and retained no item, customer, or sale frame after delivery. Identity, business/subscription, shop/device public-key metadata, short-lived authorization, and opaque key envelopes remain backend concerns.

## Remaining Release Gaps

- Pairing currently uses a text code; QR camera capture is not implemented.
- Devices must overlap online because there is no durable cloud mailbox.
- Snapshot/anti-entropy catch-up is not implemented, so a peer cannot yet recover events that are no longer present in another register's outbox.
- Operator PIN separation and SQLCipher database encryption remain pending.
- If every synchronized device is lost, the metadata-only backend cannot restore operational records.
