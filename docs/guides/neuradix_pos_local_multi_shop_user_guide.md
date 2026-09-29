# Neuradix POS Local Multi-Shop User Guide

## Purpose

Local Multi-Shop lets one business operate several shops without permanently storing its customers, inventory, or sales in Neuradix Cloud. Each shop owns its catalog and stock. Trusted registers share customers and finalized sales while they overlap online.

## Register The Business

1. Choose **Use Neuradix Cloud** and **Register**.
2. Select **Free Local** and **Local Multi-Shop**.
3. Enter the business, owner, first shop name, and unique shop code.
4. Create the business. The first register becomes a trusted register in the first shop.

## Add Shops And Registers

1. Open **My Profile** as the owner.
2. Under **Shop Management**, choose **Add Shop**.
3. On the new register, sign in, select its intended shop, and start enrollment.
4. Give the pairing code to an already trusted owner register.
5. Approve the enrollment. The new register receives an encrypted business-key envelope and joins the relay.

## Daily Selling

1. Add inventory on each shop's own register. SKU, barcode, image, price, and stock stay within that shop.
2. Add or search a customer. Customers synchronize across the business.
3. Search an item by name, SKU, or barcode. Compatible hardware barcode scanners can type into the barcode field.
4. Add the item to the cart, review quantity and total, then record the sale.
5. Only finalized sales synchronize. Drafts and parked carts stay on the current register.

## Offline Work

- Sales and customer changes are committed to SQLite before synchronization.
- The header shows **Offline / Queued**, pending-event count, and last successful sync.
- Keep working. Do not uninstall the app or clear application data.
- Reconnect this register and at least one trusted register. The relay retries automatically.
- The relay is not a mailbox, so both devices must overlap online before queued changes can transfer.

## Verify Synchronization

1. Confirm both registers show **Live Relay**.
2. Wait until **Pending: 0**.
3. Open **History** on each register and compare the finalized-sale set.
4. Confirm customer changes appear in both shops.
5. Confirm each shop still shows only its own inventory and stock.

## Reassign A Register

- Only the owner can move a trusted register to another shop.
- Reassignment is blocked while the register has pending events, a non-empty cart, or parked work.
- After confirmation, the old shop catalog is cleared and the app remounts in the new shop.
- Customers and finalized sales remain because they are business-wide.

## Troubleshooting

- **Offline / Queued:** verify internet access and keep another trusted register online.
- **Pairing Required:** select the correct shop and obtain approval from a trusted owner register.
- **Pending does not reach zero:** leave both registers open and online, then use Refresh.
- **Wrong shop inventory:** stop selling, confirm the Shop badge, and ask the owner to review register assignment.
- **Lost device:** revoke it from Shop Management as soon as possible.

## Recovery Warning

Neuradix Cloud stores identity and trusted-device metadata, not free-tier operational payloads. If every synchronized device is lost, local customers, sales, and inventory cannot be restored from Neuradix Cloud.
