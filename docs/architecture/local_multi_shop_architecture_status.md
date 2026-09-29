# Local Multi-Shop Architecture Status

Updated: 2026-09-29

## Implemented

- Atomic business plus first-shop registration for `free_local + local_multi_shop`.
- Owner Shop Management for shop creation and trusted-register visibility.
- Shop selection before second-register enrollment and trusted-device approval.
- Device-bound Ed25519 signing keys, X25519 key exchange, AES-GCM payload encryption, and opaque business-key envelopes.
- Short-lived relay tokens bound to business, trusted device, key epoch, protocol version, and shop.
- Stateless WebSocket relay with same-shop inventory routing and business-wide customer/finalized-sale routing.
- Durable SQLite outbox/inbox, acknowledgement ledger, duplicate handling, conflict records, and hybrid logical clocks.
- Shop-local items, prices, barcodes, images, and stock.
- Business-wide customers and immutable finalized-sale snapshots.
- Reassignment safety checks plus shop-local cache clearing and shell remount.
- Pending count, assigned shop, relay state, last successful sync, and offline recovery guidance.
- Shared-cloud persistence endpoints reject Local Multi-Shop operational writes.

## Data Boundaries

Device-only operational data:

- Item master, price, barcode, image reference, and stock for the assigned shop.
- Customer records replicated between trusted business devices.
- Finalized sales and line snapshots replicated between trusted business devices.
- Draft carts, parked carts, incomplete sales, and local UI settings.
- Plaintext business keys and decrypted event payloads.

Neuradix metadata service:

- User identity, business, membership, subscription, shops, trusted devices, public keys, enrollment state, and opaque key envelopes.
- No Local Multi-Shop Product, Customer, Sale, or Sale Item rows.

Stateless relay memory:

- Encrypted signed frames only while sender and eligible recipients overlap online.
- No durable mailbox and no payload logging.

## Subscription Modes

- Free Local Multi-Shop: metadata-only backend; local inventory; peer-synchronized customers and finalized sales.
- Shared Cloud Starter: capped products, customers, sales, and sale lines in shared Neuradix doctypes with business isolation.
- Shared Cloud Paid: same shared model with higher or unrestricted configured limits.
- Dedicated Backend: complete client data persists through its configured connector backend. ERPNext is currently supported; Odoo and Neuradix Atlas Team are planned connector targets.

## Known Limitations

- Production must use HTTPS and WSS; the certification endpoint is plaintext test infrastructure.
- Devices must overlap online because the relay has no durable mailbox.
- QR camera pairing, operator PIN separation, SQLCipher, and snapshot/anti-entropy recovery remain future hardening.
- Local replicas are the only operational backups. If every synchronized device is lost, Neuradix Cloud cannot recover free-tier business data.
