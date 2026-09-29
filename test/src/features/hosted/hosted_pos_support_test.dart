import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/hosted/hosted_models.dart';
import 'package:neuradix_pos/src/features/hosted/hosted_pos_support.dart';

void main() {
  const customer = HostedCustomer(
    customerId: 'NCUST-0001',
    customerCode: 'CUS-001',
    displayName: 'Neighbourhood Grocer',
    mobileNo: '99880011',
    emailId: 'grocer@example.com',
    primaryAddress: 'Valletta',
    isActive: true,
  );

  const inventoryItem = HostedInventoryItem(
    itemId: 'NPROD-0001',
    sku: 'COFFEE-001',
    barcode: '5353535353',
    displayName: 'Classic Blend Beans',
    imageUrl: '',
    price: 11.5,
    stockQty: 18,
    isActive: true,
  );

  test('customer matching searches name, code, and mobile', () {
    expect(
      hostedCustomerSearchLabel(customer),
      'CUS-001 • Neighbourhood Grocer',
    );
    expect(hostedCustomerMatchesQuery(customer, 'grocer'), isTrue);
    expect(hostedCustomerMatchesQuery(customer, 'CUS-001'), isTrue);
    expect(hostedCustomerMatchesQuery(customer, '9988'), isTrue);
    expect(hostedCustomerMatchesQuery(customer, 'missing'), isFalse);
  });

  test('inventory matching searches name, sku, and barcode', () {
    expect(
      hostedInventorySearchLabel(inventoryItem),
      'Classic Blend Beans • COFFEE-001 • 5353535353',
    );
    expect(hostedInventoryMatchesQuery(inventoryItem, 'blend'), isTrue);
    expect(hostedInventoryMatchesQuery(inventoryItem, 'COFFEE-001'), isTrue);
    expect(hostedInventoryMatchesQuery(inventoryItem, '5353535353'), isTrue);
    expect(hostedInventoryMatchesQuery(inventoryItem, 'missing'), isFalse);
    expect(
      findHostedInventoryExactMatch(const <HostedInventoryItem>[
        inventoryItem,
      ], '5353535353')?.itemId,
      'NPROD-0001',
    );
  });

  test('image helpers build and decode local data uris', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final dataUri = hostedImageDataUri(fileName: 'coffee.png', bytes: bytes);

    expect(dataUri, startsWith('data:image/png;base64,'));
    expect(decodeHostedImageDataUri(dataUri), bytes);
  });

  test('image helpers resolve relative hosted file urls', () {
    expect(
      hostedResolveImageUrl(
        imageUrl: '/files/coffee.png',
        baseUrl: 'http://127.0.0.1:8018',
      ),
      'http://127.0.0.1:8018/files/coffee.png',
    );
    expect(hostedImageMimeTypeFromFileName('coffee.jpeg'), 'image/jpeg');
    expect(
      base64Decode(
        hostedImageDataUri(
          fileName: 'coffee.png',
          bytes: Uint8List.fromList(<int>[5]),
        ).split(',').last,
      ),
      Uint8List.fromList(<int>[5]),
    );
  });

  test('cloud create helpers strip temporary local ids before sync', () {
    final preparedInventory = normalizeHostedInventoryDraftForSave(
      const HostedInventoryItem(
        itemId: 'item-1723620000000',
        sku: 'COFFEE-001',
        barcode: '5353535353',
        displayName: 'Classic Blend Beans',
        imageUrl: '',
        price: 11.5,
        stockQty: 18,
        isActive: true,
      ),
      syncToCloud: true,
    );
    final preparedCustomer = normalizeHostedCustomerDraftForSave(
      const HostedCustomer(
        customerId: 'customer-1723620000000',
        customerCode: 'CUS-001',
        displayName: 'Neighbourhood Grocer',
        mobileNo: '99880011',
        emailId: 'grocer@example.com',
        primaryAddress: 'Valletta',
        isActive: true,
      ),
      syncToCloud: true,
    );

    expect(preparedInventory.itemId, isEmpty);
    expect(preparedCustomer.customerId, isEmpty);
  });

  test(
    'local create helpers generate deterministic offline ids when missing',
    () {
      final timestamp = DateTime.utc(2026, 8, 14, 10, 30, 0);
      final preparedInventory = normalizeHostedInventoryDraftForSave(
        const HostedInventoryItem(
          itemId: '',
          sku: 'COFFEE-001',
          barcode: '5353535353',
          displayName: 'Classic Blend Beans',
          imageUrl: '',
          price: 11.5,
          stockQty: 18,
          isActive: true,
        ),
        syncToCloud: false,
        timestamp: timestamp,
      );
      final preparedCustomer = normalizeHostedCustomerDraftForSave(
        const HostedCustomer(
          customerId: '',
          customerCode: 'CUS-001',
          displayName: 'Neighbourhood Grocer',
          mobileNo: '99880011',
          emailId: 'grocer@example.com',
          primaryAddress: 'Valletta',
          isActive: true,
        ),
        syncToCloud: false,
        timestamp: timestamp,
      );

      expect(preparedInventory.itemId, hostedLocalInventoryId(timestamp));
      expect(preparedCustomer.customerId, hostedLocalCustomerId(timestamp));
    },
  );

  test('clears the cart after a sale is safely queued locally', () {
    const cart = <HostedSaleLine>[
      HostedSaleLine(
        itemId: 'NPROD-0001',
        displayName: 'Classic Blend Beans',
        qty: 1,
        rate: 11.5,
      ),
    ];

    expect(
      hostedCartAfterSaleFailure(currentCart: cart, savedLocally: true),
      isEmpty,
    );
    expect(
      hostedCartAfterSaleFailure(currentCart: cart, savedLocally: false),
      cart,
    );
  });

  test('blocks shop reassignment while local work remains', () {
    expect(
      localSyncShopReassignmentBlockReason(
        pendingEvents: 0,
        parkedOrders: 0,
        queuedOrders: 0,
        activeCartLines: 1,
      ),
      contains('active cart'),
    );
    expect(
      localSyncShopReassignmentBlockReason(
        pendingEvents: 2,
        parkedOrders: 1,
        queuedOrders: 0,
        activeCartLines: 0,
      ),
      contains('2 sync event(s)'),
    );
    expect(
      localSyncShopReassignmentBlockReason(
        pendingEvents: 0,
        parkedOrders: 0,
        queuedOrders: 0,
        activeCartLines: 0,
      ),
      isNull,
    );
  });
}
