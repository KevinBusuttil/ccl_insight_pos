# Neuradix POS Client Brochure

**Document status:** Client review edition

**Product status language:** Every capability is marked Available Today or Proposed - Not Yet Implemented.

**Pricing:** Intentionally excluded.

## Page 1 - Cover

### Neuradix POS

**Sell Anywhere. Stay in Control.**

Local-first point of sale for independent shops, multi-location brands, and businesses connected to a dedicated ERPNext environment.

## Page 2 - One POS, Three Ways To Operate

### Local-first by design

Neuradix POS keeps selling workflows fast and usable even when connectivity is unreliable. The same Flutter application adapts to phones, tablets, and PCs while allowing each business to choose the deployment model that fits its operations.

**Available Today**

- Responsive phone, tablet, and desktop layouts.
- Device-local SQLite storage and cached operational data.
- Connection to a shared Neuradix Cloud business or a dedicated compatible backend.
- Android, iOS, and Windows project targets; release packaging remains a deployment activity.

## Page 3 - Choose The Right Deployment

### Device Local

**Available Today** - Inventory, customers, and sales remain on one device after hosted account registration. Best for a single independent shop that does not need cross-device history.

### Local Multi-Shop

**Proposed - Not Yet Implemented** - Customers and finalized sales move between authorized shop devices without permanent business-data storage in Neuradix Cloud. Items and stock remain local to each shop.

### Cloud Or Dedicated ERP

**Available Today** - Use the shared Neuradix backend or connect the POS to a company's dedicated Frappe/ERPNext bench for persistent server-backed operations.

## Page 4 - From Customer To Completed Sale

**Available Today**

1. Select or create a customer.
2. Search products by name or SKU, or enter a barcode with a compatible hardware scanner.
3. Add products to the cart and adjust quantities or notes.
4. Review pricing, tax, subtotal, and total.
5. Record or submit the sale or order.
6. Open history to review the transaction and its line details.

The POS does not currently claim camera-based barcode scanning. Barcode workflows use the barcode entry field and scanners that behave as keyboard input.

## Page 5 - Products And Customers At The Counter

**Available Today**

- Create inventory records with SKU, barcode, name, image, price, stock, and active status.
- Select an item image from local device storage.
- Filter inventory as the operator types and add an exact barcode or SKU match.
- Create customers with contact and address details.
- Search customers progressively by code, name, or phone.
- Keep a selected customer attached to the sale composer.
- Open completed sales to review customer, date, status, total, and sale lines.

## Page 6 - Keep Selling When The Connection Drops

**Available Today**

- SQLite provides the local source of truth for cached and local workflows.
- Device-local modes can create inventory, customers, and sales without cloud persistence.
- Dedicated-backend mode caches assigned customers, catalog data, customer pricing, images, visit plans, order history, and policy data.
- Orders can be parked locally and submitted later.
- Queued replay uses stable client order IDs to prevent duplicate remote orders.
- Sync indicators and logout guards make pending work visible.

## Page 7 - Dedicated Business Operations

**Available Today**

For organizations with their own ERPNext/Frappe environment, Neuradix POS supports a centrally managed catalog with representative-specific customer visibility.

- Shared item catalog across the company.
- Customers restricted to their assigned sales representative.
- Customer-specific prices and account policies.
- Minimum-order rules with recorded exception notes.
- Visit-plan creation, sequencing, movement, and daily synchronization.
- Customer statements, credit status, payment terms, and outstanding balances.
- Parked orders, offline queues, order replay, and order history.
- Backend-generated sales orders and centralized ERP visibility.

## Page 8 - The Proposed ABP Multi-Shop Experience

**Proposed - Not Yet Implemented**

ABP can operate five shops with independent item ranges and stock while maintaining one shared customer relationship across the brand.

- Each shop owns its catalog, prices, barcodes, and stock.
- Customer records replicate to authorized ABP devices.
- Finalized sales replicate with immutable item-line snapshots.
- A customer visiting another ABP shop can have synchronized history available locally.
- Drafts and parked carts do not replicate; they stay at the shop where they were created.
- Local staff PINs preserve operator attribution without requiring a cloud user for every cashier.

## Page 9 - How A Sale Reaches Another Shop

**Proposed - Not Yet Implemented**

1. Shop A commits a finalized sale to encrypted local storage.
2. The POS creates a signed, encrypted synchronization event in the same local transaction.
3. A live Neuradix relay routes the unreadable event to online authorized peers.
4. The preferred replica or another shop verifies and commits the event locally.
5. The receiving device acknowledges only after durable local storage.
6. Shop B reads the synchronized customer history from its own local database.

If no peer is online, Shop A retains the event and retries later. The relay is not a durable mailbox.

## Page 10 - No Permanent Cloud Storage For Business Data

### Stored on authorized business devices

**Proposed - Not Yet Implemented** - Customer details, finalized sales, sale-line snapshots, conflict history, local operator information, and synchronization events.

### Retained by Neuradix Cloud

**Proposed - Not Yet Implemented** - Identity, subscription state, shop and device registration, public keys, encrypted device-key envelopes, revocation state, and short-lived relay authorization.

### Routed but not retained

**Proposed - Not Yet Implemented** - End-to-end encrypted customer and sales frames pass through the live relay while peers are online. The relay cannot decrypt them and does not retain their payloads.

**Accurate promise:** No permanent business-data storage in Neuradix Cloud for local multi-shop mode.

Neuradix infrastructure still provides identity, subscriptions, public keys, device registration, and temporary encrypted routing. Operational business payloads remain on authorized devices.

## Page 11 - Trust Every Device Before It Joins

**Proposed - Not Yet Implemented**

- A new device signs in and displays a one-time QR enrollment challenge.
- An existing trusted device checks the fingerprint and approves it.
- The business encryption key is transferred only as a device-specific encrypted envelope.
- Signed events provide origin and tamper verification.
- Revocation blocks future relay access and starts a new encryption-key epoch.
- Previously synchronized data cannot be remotely removed from a revoked device.

### Operational limits

- Devices must overlap online to transfer data.
- Mobile operating systems can suspend inactive applications.
- History may be stale until a replica reconnects.
- Replica-only recovery cannot restore data after every copy is lost.

## Page 12 - Capability Matrix And Client Review

| Capability | Device Local | Local Multi-Shop | Shared Cloud | Dedicated ERP |
| --- | --- | --- | --- | --- |
| Local selling | Available Today | Proposed | Available Today | Available Today |
| Customer records | One device | Replicated locally | Shared cloud | ERP-managed |
| Finalized sales | One device | Replicated locally | Shared cloud | ERP-managed |
| Items and stock | One device | Local per shop | Shared cloud | Company catalog |
| Permanent Neuradix business-data storage | No | No | Yes | No - customer bench |
| Offline work | Available Today | Proposed | Available Today | Available Today |
| Multi-device history | No | Proposed | Server-backed | Server-backed |

### Client review points

- Confirm that customers and finalized sales are the only replicated business records.
- Confirm that catalog and stock stay shop-local.
- Accept overlap-online synchronization without a durable cloud mailbox.
- Accept replica-only recovery or request a separate customer-owned backup option.
- Decide commercial plan assignment and device limits later.
