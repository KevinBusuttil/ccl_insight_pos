# Neuradix Local Multi-Shop Sync

**Status:** Implementation In Progress - Foundation Complete

**Decision date:** 2026-09-21

**Implementation started:** 2026-09-22

**Purpose:** Preserve the approved architecture, record the delivered foundation, and keep later phases explicit.

## Implementation Progress

### Available In The Current Foundation

- Hosted registration and bootstrap understand `sync_mode = local_multi_shop` independently from commercial plan names.
- The Flutter registration screen exposes Local Multi-Shop when the backend feature flag is enabled.
- The metadata backend stores businesses, shops, trusted-device public keys, enrollment challenges, opaque key envelopes, preferred-peer state, revocation state, protocol version, and relay authorization metadata.
- Local Multi-Shop operational APIs are metadata-only. Hosted item, customer, and sale persistence is rejected for this sync mode.
- Relay tokens are short-lived, signed, and bound to the business, device, key epoch, and protocol version.
- Flutter creates Ed25519 signing keys, X25519 exchange keys, and a 256-bit AES-GCM business key in platform secure storage for the first trusted device.
- SQLite schema version 6 contains the local sync profile, peers, outbox/inbox events, acknowledgements, entity/field versions, and conflict records.
- Customer writes and finalized-sale writes atomically update the local materialized tables and append signed, encrypted outbox events.
- Receiving replicas reject cross-business, untrusted-device, wrong-epoch, invalid-signature, and altered-ciphertext events.
- Customer fields merge deterministically with hybrid logical clocks. Finalized sales are immutable and retain item snapshots.
- Automated two-replica tests prove that customers and finalized sales replicate while inventory, stock, drafts, and parked carts remain local.

### Required Before Production Release

- Deploy the stateless WebSocket relay and connect the Flutter outbox/inbox worker to it.
- Add the owner-facing QR enrollment, approval, key-unwrapping, preferred-device, and revocation screens. The backend contracts and Flutter API client methods exist, but the complete screens do not.
- Add acknowledgement retry, version-vector exchange, signed snapshot onboarding, interrupted-snapshot recovery, and long-partition anti-entropy.
- Add device-local staff profiles/PINs and preserve operator attribution in finalized-sale events.
- Move the SQLite database itself to an encrypted database implementation; sync payloads and private key material are already encrypted, but the current SQLite file is not SQLCipher-encrypted.
- Add customer duplicate review/merge, void/refund/correction events, per-shop history filters, stale-state indicators, and replica-loss warnings.
- Complete Android, iOS, and Windows device testing and the five-shop fault/security test matrix below.

## Objective

Allow a multi-location business such as ABP to operate Neuradix POS from local device storage while sharing customer records and finalized sales between authorized shops. Neuradix Cloud must not permanently store operational customer or sales payloads for this mode.

## Approved Product Decisions

- The commercial plan name remains undecided. The capability is exposed independently through `sync_mode` and feature flags.
- Neuradix Cloud may retain account, subscription, shop, device, public-key, encrypted key-envelope, revocation, and relay-authorization metadata.
- A stateless Neuradix relay may route end-to-end encrypted frames while devices are online, but it must not persist operational payloads.
- Every authorized device retains a local replica of customers and finalized sales.
- Item masters, prices, barcodes, images, and stock remain local to each shop and do not replicate.
- Replicated sale lines carry immutable snapshots of the originating shop's item code, barcode, name, quantity, rate, discount, tax, and totals.
- Draft sales and parked carts remain on their originating device.
- A preferred POS device acts as the most complete peer only while its app is open. Any two online authorized devices may still synchronize.
- V1 platforms are Android, iPhone/iPad, and Windows.
- The owner enrolls a new device by approving a one-time QR challenge from an already trusted device.
- Staff use device-local operator profiles and PINs. Finalized sales preserve operator attribution.
- Recovery depends on surviving synchronized replicas. There is no automatic Neuradix Cloud backup in this model.

## Data Flow

1. A shop creates or updates a customer, or finalizes a sale, in its local encrypted SQLite database.
2. The same local transaction updates the materialized record and appends a signed synchronization event.
3. The device requests a short-lived relay token from the Neuradix metadata backend.
4. The device sends the encrypted event through the live WebSocket relay to online authorized peers.
5. A receiving peer verifies the signature, decrypts the event, commits it locally, and then acknowledges durable storage.
6. The source retains unsent events and retries after interruption. It never treats relay receipt alone as durable synchronization.
7. Peers exchange version vectors to find missing events and can stream a signed snapshot when onboarding a new device.
8. Customer searches and sales-history requests use the local replica immediately and show when it was last synchronized.

## Consistency Rules

- Customer records use generated global IDs.
- Normalized phone numbers identify possible duplicates but never trigger an automatic merge.
- Customer fields use deterministic per-field versions based on hybrid logical clocks and device-ID tie-breaking.
- Duplicate customers require an owner-reviewed merge event that maps old IDs to one canonical ID.
- Finalized sales are immutable. Voids, refunds, and corrections are linked events rather than edits.
- A sale received from another shop never changes the receiving shop's catalog or stock.
- Device revocation prevents future relay access and triggers a new encryption-key epoch, but cannot erase data already copied to the revoked device.

## Security Boundary

- Device signing keys use Ed25519.
- Device key exchange uses X25519 with HKDF-derived wrapping keys.
- Event and snapshot payloads use authenticated AES-256-GCM encryption.
- Private keys and the local database key live in platform secure storage.
- The first trusted device creates the business encryption key.
- The metadata backend stores only a device-specific encrypted key envelope; it cannot decrypt business payloads.
- Relay logs and metrics may include connection timing, frame counts, and byte counts, but never ciphertext bodies or decrypted content.

## Metadata Interfaces

The hosted bootstrap response exposes `sync_mode`, `relay_url`, `protocol_version`, `max_devices`, `metadata_only`, and `feature_local_multi_shop_sync`.

Metadata APIs now cover shop registration, enrollment challenges, trusted-device approval, enrollment completion, device listing, revocation, preferred-peer selection, and short-lived relay-token issuance. There is no server API for storing customer or sale events in this mode.

## User Experience

- Setup identifies the business and shop, registers the first device, and creates local operator PINs.
- A new device displays an expiring QR challenge for approval by a trusted device.
- The POS shows Local, Waiting for Peer, Shared, Stale, and Conflict synchronization states.
- Customer history combines finalized sales from all synchronized shops and can be filtered by shop.
- The inventory and stock screens remain shop-specific.
- Logout, database reset, and device removal warn when local events have not reached another replica.

## Constraints To Communicate

- This is not a serverless system: Neuradix still provides identity, device metadata, and live encrypted routing.
- There is no permanent business-data storage in Neuradix Cloud for this mode.
- Devices must overlap online because the relay has no durable mailbox.
- Mobile operating systems may suspend synchronization when the app is not active.
- History can be stale until another replica is reachable.
- A source device lost before another peer acknowledges its latest events can lose those records.
- Losing every synchronized replica permanently loses the business data.

## Compatibility

- Existing `free_local`, `free_cloud`, `paid_cloud`, and dedicated-backend behavior remains unchanged unless Local Multi-Shop is explicitly selected and enabled by the site feature flag.
- Dedicated benches continue storing business data in ERPNext/Frappe.
- Shared-cloud plans continue storing operational rows on the hosted Neuradix bench.
- Pricing and subscription assignment for local multi-shop sync remain out of scope.

## Required Validation Before Release

- Migrate the current local schema without losing existing customers, inventory, or sales.
- Simulate five shops across long partitions, duplicate delivery, out-of-order events, interrupted snapshots, and reconnects.
- Verify customer conflict handling, duplicate review, sale immutability, refunds, and shop-local stock.
- Reject forged signatures, altered ciphertext, expired tokens, revoked devices, and cross-business traffic.
- Confirm Android, iOS, and Windows key storage and encrypted database behavior.
- Audit Frappe tables, Redis, relay logs, metrics, and relay disks to prove that no operational payload is retained.
