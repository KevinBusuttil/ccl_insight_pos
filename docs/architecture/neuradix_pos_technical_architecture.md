# Neuradix POS Technical Architecture

## System Boundary

The Flutter application owns the operational SQLite database. Frappe provides identity, subscriptions, shop/device metadata, enrollment, public keys, opaque encrypted key envelopes, and short-lived relay authorization. The WebSocket relay is stateless and routes encrypted signed frames only to currently connected eligible peers.

## Event Scope

| Entity | Scope | Durable Location |
| --- | --- | --- |
| Inventory item, price, barcode, image reference, stock | Same shop | Trusted registers assigned to that shop |
| Customer | Whole business | Trusted registers in every shop |
| Finalized sale and immutable line snapshots | Whole business | Trusted registers in every shop |
| Draft, parked cart, incomplete sale, local setting | This register only | Current register SQLite |

## Write Flow

1. SQLite commits the operational record and outgoing event in one transaction.
2. The client encrypts the payload with the business key and signs the envelope with the device key.
3. A short-lived token binds the connection to business, trusted device, shop, key epoch, and protocol.
4. The relay validates claims and origin shop, then selects eligible online peers by event scope.
5. A receiving device verifies trust/signature, decrypts, validates scope, and commits inbox plus data atomically.
6. The receiver acknowledges only after durable apply.
7. The source settles an event after all currently required trusted peers acknowledge it.

## Security

- Ed25519 authenticates event origin.
- X25519 protects business-key enrollment envelopes.
- AES-GCM protects operational event payloads.
- Public keys and opaque key envelopes may be stored by Frappe; plaintext business keys may not.
- Relay frames are not logged or persisted.
- Repository scope checks reject incorrectly routed inventory and cross-business envelopes.

## Storage

SQLite stores hosted configuration, local products, customers, sales, sale lines, outbox/inbox events, peer acknowledgements, conflicts, and sync diagnostics. Secure platform storage holds private device material. Frappe stores only metadata for Local Multi-Shop. No Local Multi-Shop Product, Customer, Sale, or Sale Item rows are persisted there. Shared Cloud and Dedicated modes intentionally use different persistence boundaries.

## APIs

- `register_business`: creates owner, business, membership, subscription, optional device, and first shop atomically.
- `get_metadata`: returns shops, trusted devices, enrollment state, and relay configuration.
- `create_shop`: owner-only shop creation with case-insensitive unique code enforcement.
- `start_enrollment`: starts or resumes an expiring request for a selected shop.
- `approve_enrollment`: trusted owner wraps and approves the business key.
- `complete_enrollment`: new register accepts its envelope and becomes trusted.
- `issue_relay_token`: issues a short-lived token that includes `shop_id`.

## Subscription Models

- Free Local Multi-Shop stores no operational rows in Neuradix Cloud.
- Shared Cloud Starter persists operational rows in shared Neuradix doctypes with configured caps and mandatory business filters.
- Shared Cloud Paid uses the same model with higher or unrestricted settings.
- Dedicated Backend persists complete business data through the selected backend connector. ERPNext is one supported connector rather than a required universal storage model; Odoo and Neuradix Atlas Team are planned connector targets.

## Certification

The 2026-09-29 server certification used two Android emulators and the deployed metadata/relay services. It verified 18 converged sales, six converged customers, four isolated items per shop, zero pending events, duplicate protection, restart durability, and zero hosted operational rows.

## Operational Limits

- Stateless delivery requires online overlap.
- There is no server-side business-data recovery for Local Multi-Shop.
- Production requires TLS, relay supervision, monitoring, key-revocation procedures, and a documented device-backup policy.
- Snapshot/anti-entropy recovery, QR camera pairing, operator PINs, and SQLCipher are not yet implemented.
