import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/hosted_local_repository.dart';
import 'package:neuradix_pos/src/data/local/local_sync_repository.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/hosted/hosted_models.dart';
import 'package:neuradix_pos/src/features/local_sync/hybrid_logical_clock.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_coordinator.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_crypto.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_models.dart';
import 'package:neuradix_pos/src/features/orders/local_order_repository.dart';
import 'package:neuradix_pos/src/features/orders/order_models.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'two shops replicate customers and finalized sales but not local stock or parked carts',
    () async {
      sqfliteFfiInit();
      final databaseDirectory = await databaseFactoryFfi.getDatabasesPath();
      final firstDatabasePath = path.join(
        databaseDirectory,
        'neuradix_local_sync_shop_1.db',
      );
      final secondDatabasePath = path.join(
        databaseDirectory,
        'neuradix_local_sync_shop_2.db',
      );
      await databaseFactoryFfi.deleteDatabase(firstDatabasePath);
      await databaseFactoryFfi.deleteDatabase(secondDatabasePath);
      final firstDatabaseOwner = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: firstDatabasePath,
      );
      final secondDatabaseOwner = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: secondDatabasePath,
      );
      final firstDatabase = await firstDatabaseOwner.open();
      final secondDatabase = await secondDatabaseOwner.open();
      final firstRepository = LocalSyncRepository(firstDatabase);
      final secondRepository = LocalSyncRepository(secondDatabase);
      const firstProfile = LocalSyncProfile(
        businessId: 'business-abp',
        shopId: 'shop-1',
        shopName: 'ABP Shop 1',
        deviceId: 'device-1',
        deviceName: 'Till 1',
        relayUrl: 'wss://relay.invalid',
        protocolVersion: 1,
        keyEpoch: 1,
      );
      const secondProfile = LocalSyncProfile(
        businessId: 'business-abp',
        shopId: 'shop-2',
        shopName: 'ABP Shop 2',
        deviceId: 'device-2',
        deviceName: 'Till 2',
        relayUrl: 'wss://relay.invalid',
        protocolVersion: 1,
        keyEpoch: 1,
      );
      await firstRepository.saveProfile(firstProfile);
      await secondRepository.saveProfile(secondProfile);

      final firstKeys = await LocalSyncKeyManager(
        secureStore: InMemoryLocalSyncSecureStore(),
      ).loadOrCreateFirstDeviceKeys(
        businessId: firstProfile.businessId,
        deviceId: firstProfile.deviceId,
      );
      final generatedSecondKeys = await LocalSyncKeyManager(
        secureStore: InMemoryLocalSyncSecureStore(),
      ).loadOrCreateFirstDeviceKeys(
        businessId: secondProfile.businessId,
        deviceId: secondProfile.deviceId,
      );
      final secondKeys = LocalSyncDeviceKeys(
        signingPrivateKey: generatedSecondKeys.signingPrivateKey,
        signingPublicKey: generatedSecondKeys.signingPublicKey,
        exchangePrivateKey: generatedSecondKeys.exchangePrivateKey,
        exchangePublicKey: generatedSecondKeys.exchangePublicKey,
        businessKey: firstKeys.businessKey,
        keyEpoch: 1,
      );
      await firstRepository.upsertPeer(
        deviceId: secondProfile.deviceId,
        shopId: secondProfile.shopId,
        deviceName: secondProfile.deviceName,
        signingPublicKey: secondKeys.signingPublicKeyBase64,
        exchangePublicKey: secondKeys.exchangePublicKeyBase64,
        status: 'active',
        keyEpoch: 1,
      );
      await secondRepository.upsertPeer(
        deviceId: firstProfile.deviceId,
        shopId: firstProfile.shopId,
        deviceName: firstProfile.deviceName,
        signingPublicKey: firstKeys.signingPublicKeyBase64,
        exchangePublicKey: firstKeys.exchangePublicKeyBase64,
        status: 'active',
        keyEpoch: 1,
      );

      final firstCoordinator = LocalSyncCoordinator(
        profile: firstProfile,
        keys: firstKeys,
        repository: firstRepository,
        clock: HybridLogicalClock(
          nodeId: firstProfile.deviceId,
          now: () => DateTime.utc(2026, 9, 21, 12),
        ),
        eventIdGenerator: _sequentialIds('event-a'),
      );
      final secondCoordinator = LocalSyncCoordinator(
        profile: secondProfile,
        keys: secondKeys,
        repository: secondRepository,
        clock: HybridLogicalClock(
          nodeId: secondProfile.deviceId,
          now: () => DateTime.utc(2026, 9, 21, 12, 1),
        ),
      );

      final secondHostedRepository = HostedLocalRepository(secondDatabase);
      const shopOneItem = HostedInventoryItem(
        itemId: 'shop-1-item',
        sku: 'ABP-COFFEE',
        barcode: '535300000001',
        displayName: 'Shop 1 Coffee',
        imageUrl: '',
        price: 7.5,
        stockQty: 10,
        isActive: true,
      );
      await firstCoordinator.saveInventoryItem(shopOneItem);
      await LocalOrderRepository(firstDatabase).saveParkedOrder(
        const LocalOrder(
          clientOrderId: 'parked-1',
          customerId: 'customer-1',
          totalAmount: 7.5,
          payloadJson: '{}',
          status: 'parked',
          updatedAtIso: '2026-09-21T12:00:00Z',
        ),
      );
      expect(await firstRepository.pendingEventCount(), 1);

      const customer = HostedCustomer(
        customerId: 'customer-global-1',
        customerCode: 'ABP-C001',
        displayName: 'Shared Customer',
        mobileNo: '99001122',
        emailId: 'customer@example.com',
        primaryAddress: 'Valletta',
        isActive: true,
        updatedAt: '2026-09-21T12:00:00Z',
      );
      const sale = HostedSaleRecord(
        saleId: 'sale-global-1',
        remoteSaleId: '',
        customerId: 'customer-global-1',
        customerName: 'Shared Customer',
        postingDate: '2026-09-21',
        totalAmount: 15,
        status: 'local_only',
        updatedAt: '2026-09-21T12:00:00Z',
        items: <HostedSaleLine>[
          HostedSaleLine(
            itemId: 'shop-1-item',
            sku: 'ABP-COFFEE',
            barcode: '535300000001',
            displayName: 'Shop 1 Coffee',
            qty: 2,
            rate: 7.5,
          ),
        ],
      );
      await firstCoordinator.saveCustomer(customer);
      await firstCoordinator.saveFinalizedSale(sale);
      expect(await firstRepository.pendingEventCount(), 3);

      final pending = await firstRepository.readPendingEvents();
      for (final event in pending) {
        final result = await secondCoordinator.applyEnvelope(event.envelope);
        expect(
          result.materialized,
          event.envelope.entityType != LocalSyncEntityType.inventoryItem,
        );
        final duplicate = await secondCoordinator.applyEnvelope(event.envelope);
        expect(duplicate.isDuplicate, isTrue);
        await firstRepository.acknowledge(
          eventId: event.envelope.eventId,
          peerDeviceId: secondProfile.deviceId,
        );
      }

      final replicatedCustomers = await secondHostedRepository.listCustomers();
      final replicatedSales = await secondHostedRepository.listSales();
      expect(replicatedCustomers.single.customerId, customer.customerId);
      expect(replicatedSales.single.saleId, sale.saleId);
      expect(replicatedSales.single.status, 'replicated');
      expect(replicatedSales.single.items.single.sku, 'ABP-COFFEE');
      expect(replicatedSales.single.items.single.barcode, '535300000001');
      expect(await secondHostedRepository.listInventoryItems(), isEmpty);
      expect(
        await LocalOrderRepository(secondDatabase).listParkedOrders(),
        isEmpty,
      );
      expect(await firstRepository.pendingEventCount(), 0);

      await firstDatabaseOwner.close();
      await secondDatabaseOwner.close();
      await databaseFactoryFfi.deleteDatabase(firstDatabasePath);
      await databaseFactoryFfi.deleteDatabase(secondDatabasePath);
    },
  );

  test('registers in the same shop replicate shop-local inventory', () async {
    sqfliteFfiInit();
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'neuradix_local_sync_same_shop.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);
    final databaseOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final database = await databaseOwner.open();
    final repository = LocalSyncRepository(database);
    const receiverProfile = LocalSyncProfile(
      businessId: 'business-abp',
      shopId: 'shop-1',
      shopName: 'ABP Shop 1',
      deviceId: 'device-2',
      deviceName: 'Till 2',
      relayUrl: 'wss://relay.invalid',
      protocolVersion: 1,
      keyEpoch: 1,
    );
    const sourceProfile = LocalSyncProfile(
      businessId: 'business-abp',
      shopId: 'shop-1',
      shopName: 'ABP Shop 1',
      deviceId: 'device-1',
      deviceName: 'Till 1',
      relayUrl: 'wss://relay.invalid',
      protocolVersion: 1,
      keyEpoch: 1,
    );
    await repository.saveProfile(receiverProfile);
    final sourceKeys = await LocalSyncKeyManager(
      secureStore: InMemoryLocalSyncSecureStore(),
    ).loadOrCreateFirstDeviceKeys(
      businessId: sourceProfile.businessId,
      deviceId: sourceProfile.deviceId,
    );
    final generatedReceiverKeys = await LocalSyncKeyManager(
      secureStore: InMemoryLocalSyncSecureStore(),
    ).loadOrCreateFirstDeviceKeys(
      businessId: receiverProfile.businessId,
      deviceId: receiverProfile.deviceId,
    );
    final receiverKeys = LocalSyncDeviceKeys(
      signingPrivateKey: generatedReceiverKeys.signingPrivateKey,
      signingPublicKey: generatedReceiverKeys.signingPublicKey,
      exchangePrivateKey: generatedReceiverKeys.exchangePrivateKey,
      exchangePublicKey: generatedReceiverKeys.exchangePublicKey,
      businessKey: sourceKeys.businessKey,
      keyEpoch: 1,
    );
    await repository.upsertPeer(
      deviceId: sourceProfile.deviceId,
      shopId: sourceProfile.shopId,
      deviceName: sourceProfile.deviceName,
      signingPublicKey: sourceKeys.signingPublicKeyBase64,
      exchangePublicKey: sourceKeys.exchangePublicKeyBase64,
      status: 'active',
      keyEpoch: 1,
    );
    final envelope = await LocalSyncCrypto().encryptAndSign(
      profile: sourceProfile,
      keys: sourceKeys,
      eventId: 'inventory-event-1',
      entityType: LocalSyncEntityType.inventoryItem,
      entityId: 'shop-1-item',
      operation: LocalSyncOperation.upsert,
      hlc: '1000:0:device-1',
      payload: <String, Object?>{
        'schema_version': 1,
        'inventory_item':
            const HostedInventoryItem(
              itemId: 'shop-1-item',
              sku: 'ABP-COFFEE',
              barcode: '535300000001',
              displayName: 'Shop 1 Coffee',
              imageUrl: '',
              price: 7.5,
              stockQty: 10,
              isActive: true,
            ).toApiPayload(),
      },
    );
    final receiver = LocalSyncCoordinator(
      profile: receiverProfile,
      keys: receiverKeys,
      repository: repository,
      clock: HybridLogicalClock(nodeId: receiverProfile.deviceId),
    );

    final result = await receiver.applyEnvelope(envelope);

    expect(result.materialized, isTrue);
    final items = await HostedLocalRepository(database).listInventoryItems();
    expect(items.single.sku, 'ABP-COFFEE');
    expect(items.single.stockQty, 10);
    await databaseOwner.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test(
    'acknowledges inventory from same-shop peers and shared records from all peers',
    () async {
      sqfliteFfiInit();
      final databasePath = path.join(
        await databaseFactoryFfi.getDatabasesPath(),
        'neuradix_local_sync_ack_scope.db',
      );
      await databaseFactoryFfi.deleteDatabase(databasePath);
      final databaseOwner = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final database = await databaseOwner.open();
      final repository = LocalSyncRepository(database);
      const profile = LocalSyncProfile(
        businessId: 'business-abp',
        shopId: 'shop-a',
        shopName: 'ABP Shop A',
        deviceId: 'device-source',
        deviceName: 'Till A1',
        relayUrl: 'wss://relay.invalid',
        protocolVersion: 1,
        keyEpoch: 1,
      );
      await repository.saveProfile(profile);
      await repository.upsertPeer(
        deviceId: 'device-same-shop',
        shopId: 'shop-a',
        deviceName: 'Till A2',
        signingPublicKey: 'same-signing-key',
        exchangePublicKey: 'same-exchange-key',
        status: 'active',
        keyEpoch: 1,
      );
      await repository.upsertPeer(
        deviceId: 'device-other-shop',
        shopId: 'shop-b',
        deviceName: 'Till B1',
        signingPublicKey: 'other-signing-key',
        exchangePublicKey: 'other-exchange-key',
        status: 'active',
        keyEpoch: 1,
      );
      final keys = await LocalSyncKeyManager(
        secureStore: InMemoryLocalSyncSecureStore(),
      ).loadOrCreateFirstDeviceKeys(
        businessId: profile.businessId,
        deviceId: profile.deviceId,
      );
      final coordinator = LocalSyncCoordinator(
        profile: profile,
        keys: keys,
        repository: repository,
        clock: HybridLogicalClock(
          nodeId: profile.deviceId,
          now: () => DateTime.utc(2026, 9, 21, 13),
        ),
        eventIdGenerator: _sequentialIds('ack-event'),
      );
      await coordinator.saveInventoryItem(
        const HostedInventoryItem(
          itemId: 'shop-a-item',
          sku: 'SHOP-A-ITEM',
          barcode: '535300000010',
          displayName: 'Shop A Item',
          imageUrl: '',
          price: 4,
          stockQty: 8,
          isActive: true,
        ),
      );
      await coordinator.saveCustomer(
        const HostedCustomer(
          customerId: 'shared-customer',
          customerCode: 'ABP-C002',
          displayName: 'Business Customer',
          mobileNo: '',
          emailId: '',
          primaryAddress: '',
          isActive: true,
          updatedAt: '2026-09-21T13:00:00Z',
        ),
      );
      final pending = await repository.readPendingEvents();
      final inventoryEvent = pending.singleWhere(
        (event) =>
            event.envelope.entityType == LocalSyncEntityType.inventoryItem,
      );
      final customerEvent = pending.singleWhere(
        (event) => event.envelope.entityType == LocalSyncEntityType.customer,
      );

      await repository.acknowledge(
        eventId: inventoryEvent.envelope.eventId,
        peerDeviceId: 'device-same-shop',
      );
      expect(await repository.pendingEventCount(), 1);

      await repository.acknowledge(
        eventId: customerEvent.envelope.eventId,
        peerDeviceId: 'device-same-shop',
      );
      expect(await repository.pendingEventCount(), 1);
      await repository.acknowledge(
        eventId: customerEvent.envelope.eventId,
        peerDeviceId: 'device-other-shop',
      );
      expect(await repository.pendingEventCount(), 0);
      expect(await repository.lastSuccessfulSyncAt(), isNotNull);

      await databaseOwner.close();
      await databaseFactoryFfi.deleteDatabase(databasePath);
    },
  );

  test(
    'requeues settled history when a new eligible peer is trusted',
    () async {
      sqfliteFfiInit();
      final databasePath = path.join(
        await databaseFactoryFfi.getDatabasesPath(),
        'neuradix_local_sync_historical_replay.db',
      );
      await databaseFactoryFfi.deleteDatabase(databasePath);
      final databaseOwner = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final database = await databaseOwner.open();
      final repository = LocalSyncRepository(database);
      const profile = LocalSyncProfile(
        businessId: 'business-abp',
        shopId: 'shop-a',
        shopName: 'ABP Shop A',
        deviceId: 'device-source',
        deviceName: 'Till A1',
        relayUrl: 'wss://relay.invalid',
        protocolVersion: 1,
        keyEpoch: 1,
      );
      await repository.saveProfile(profile);
      final keys = await LocalSyncKeyManager(
        secureStore: InMemoryLocalSyncSecureStore(),
      ).loadOrCreateFirstDeviceKeys(
        businessId: profile.businessId,
        deviceId: profile.deviceId,
      );
      final coordinator = LocalSyncCoordinator(
        profile: profile,
        keys: keys,
        repository: repository,
        clock: HybridLogicalClock(nodeId: profile.deviceId),
        eventIdGenerator: _sequentialIds('history-event'),
      );
      await coordinator.saveInventoryItem(
        const HostedInventoryItem(
          itemId: 'shop-a-item',
          sku: 'SHOP-A-ITEM',
          barcode: '535300000011',
          displayName: 'Shop A Item',
          imageUrl: '',
          price: 4,
          stockQty: 8,
          isActive: true,
        ),
      );
      await repository.markSent('history-event-1');
      expect(await repository.pendingEventCount(), 0);

      await repository.upsertPeer(
        deviceId: 'device-shop-b',
        shopId: 'shop-b',
        deviceName: 'Till B1',
        signingPublicKey: 'shop-b-signing',
        exchangePublicKey: 'shop-b-exchange',
        status: 'active',
        keyEpoch: 1,
      );
      expect(await repository.pendingEventCount(), 0);
      await repository.upsertPeer(
        deviceId: 'device-shop-a',
        shopId: 'shop-a',
        deviceName: 'Till A2',
        signingPublicKey: 'shop-a-signing',
        exchangePublicKey: 'shop-a-exchange',
        status: 'active',
        keyEpoch: 1,
      );
      expect(await repository.pendingEventCount(), 1);
      await repository.acknowledge(
        eventId: 'history-event-1',
        peerDeviceId: 'device-shop-a',
      );
      expect(await repository.pendingEventCount(), 0);

      await coordinator.saveCustomer(
        const HostedCustomer(
          customerId: 'shared-customer',
          customerCode: 'ABP-C003',
          displayName: 'Shared Customer',
          mobileNo: '',
          emailId: '',
          primaryAddress: '',
          isActive: true,
          updatedAt: '2026-09-21T14:00:00Z',
        ),
      );
      await repository.acknowledge(
        eventId: 'history-event-2',
        peerDeviceId: 'device-shop-a',
      );
      await repository.acknowledge(
        eventId: 'history-event-2',
        peerDeviceId: 'device-shop-b',
      );
      expect(await repository.pendingEventCount(), 0);
      await repository.upsertPeer(
        deviceId: 'device-shop-c',
        shopId: 'shop-c',
        deviceName: 'Till C1',
        signingPublicKey: 'shop-c-signing',
        exchangePublicKey: 'shop-c-exchange',
        status: 'active',
        keyEpoch: 1,
      );
      expect(await repository.pendingEventCount(), 1);

      await databaseOwner.close();
      await databaseFactoryFfi.deleteDatabase(databasePath);
    },
  );

  test('retains an unacknowledged encrypted event across restart', () async {
    sqfliteFfiInit();
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'neuradix_local_sync_restart.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);
    final firstOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final firstDatabase = await firstOwner.open();
    final firstRepository = LocalSyncRepository(firstDatabase);
    const profile = LocalSyncProfile(
      businessId: 'business-restart',
      shopId: 'shop-a',
      shopName: 'Restart Shop',
      deviceId: 'device-a',
      deviceName: 'Till A',
      relayUrl: 'wss://relay.invalid',
      protocolVersion: 1,
      keyEpoch: 1,
    );
    await firstRepository.saveProfile(profile);
    final keys = await LocalSyncKeyManager(
      secureStore: InMemoryLocalSyncSecureStore(),
    ).loadOrCreateFirstDeviceKeys(
      businessId: profile.businessId,
      deviceId: profile.deviceId,
    );
    final coordinator = LocalSyncCoordinator(
      profile: profile,
      keys: keys,
      repository: firstRepository,
      clock: HybridLogicalClock(
        nodeId: profile.deviceId,
        now: () => DateTime.utc(2026, 9, 21, 15),
      ),
      eventIdGenerator: () => 'restart-event-1',
    );
    await coordinator.saveCustomer(
      const HostedCustomer(
        customerId: 'restart-customer',
        customerCode: 'RST-001',
        displayName: 'Restart Customer',
        mobileNo: '',
        emailId: '',
        primaryAddress: '',
        isActive: true,
        updatedAt: '2026-09-21T15:00:00Z',
      ),
    );
    await firstRepository.markRetry(
      'restart-event-1',
      const SocketExceptionForTest('relay offline'),
    );
    final beforeRestart = (await firstRepository.readPendingEvents()).single;
    await firstOwner.close();

    final restartedOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final restartedRepository = LocalSyncRepository(
      await restartedOwner.open(),
    );
    final afterRestart = (await restartedRepository.readPendingEvents()).single;

    expect(afterRestart.envelope.encode(), beforeRestart.envelope.encode());
    expect(afterRestart.status, 'retry');
    expect(afterRestart.attemptCount, 1);
    expect(afterRestart.lastError, contains('relay offline'));
    expect(await restartedRepository.pendingEventCount(), 1);

    await restartedOwner.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('rejects a different payload for an existing finalized sale', () async {
    sqfliteFfiInit();
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'neuradix_local_sync_sale_conflict.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);
    final databaseOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final database = await databaseOwner.open();
    final repository = LocalSyncRepository(database);
    const profile = LocalSyncProfile(
      businessId: 'business-1',
      shopId: 'shop-b',
      shopName: 'Shop B',
      deviceId: 'device-b',
      deviceName: 'Till B',
      relayUrl: 'wss://relay.invalid',
      protocolVersion: 1,
      keyEpoch: 1,
    );
    await repository.saveProfile(profile);

    final sourceKeys = await LocalSyncKeyManager(
      secureStore: InMemoryLocalSyncSecureStore(),
    ).loadOrCreateFirstDeviceKeys(
      businessId: profile.businessId,
      deviceId: 'device-a',
    );
    await repository.upsertPeer(
      deviceId: 'device-a',
      shopId: 'shop-a',
      deviceName: 'Till A',
      signingPublicKey: sourceKeys.signingPublicKeyBase64,
      exchangePublicKey: sourceKeys.exchangePublicKeyBase64,
      status: 'active',
      keyEpoch: 1,
    );
    final receiverKeys = LocalSyncDeviceKeys(
      signingPrivateKey: sourceKeys.signingPrivateKey,
      signingPublicKey: sourceKeys.signingPublicKey,
      exchangePrivateKey: sourceKeys.exchangePrivateKey,
      exchangePublicKey: sourceKeys.exchangePublicKey,
      businessKey: sourceKeys.businessKey,
      keyEpoch: 1,
    );
    final coordinator = LocalSyncCoordinator(
      profile: profile,
      keys: receiverKeys,
      repository: repository,
      clock: HybridLogicalClock(nodeId: profile.deviceId),
    );
    final crypto = LocalSyncCrypto();
    Future<LocalSyncEnvelope> envelopeFor(double rate, String eventId) {
      return crypto.encryptAndSign(
        profile: const LocalSyncProfile(
          businessId: 'business-1',
          shopId: 'shop-a',
          shopName: 'Shop A',
          deviceId: 'device-a',
          deviceName: 'Till A',
          relayUrl: 'wss://relay.invalid',
          protocolVersion: 1,
          keyEpoch: 1,
        ),
        keys: sourceKeys,
        eventId: eventId,
        entityType: LocalSyncEntityType.finalizedSale,
        entityId: 'sale-1',
        operation: LocalSyncOperation.finalize,
        hlc: eventId == 'event-1' ? '1000:0:device-a' : '1001:0:device-a',
        payload: <String, Object?>{
          'sale': <String, Object?>{
            'sale_id': 'sale-1',
            'customer_id': 'customer-1',
            'customer_name': 'Customer',
            'posting_date': '2026-09-21',
            'total_amount': rate,
            'status': 'local_only',
            'items': <Map<String, Object?>>[
              <String, Object?>{
                'item_id': 'item-1',
                'item_name': 'Item',
                'qty': 1,
                'rate': rate,
              },
            ],
          },
        },
      );
    }

    expect(
      (await coordinator.applyEnvelope(await envelopeFor(5, 'event-1'))).status,
      'applied',
    );
    final conflict = await coordinator.applyEnvelope(
      await envelopeFor(7, 'event-2'),
    );

    expect(conflict.isConflict, isTrue);
    expect(await repository.conflictCount(), 1);
    expect(
      (await HostedLocalRepository(database).listSales()).single.totalAmount,
      5,
    );
    await databaseOwner.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });
}

String Function() _sequentialIds(String prefix) {
  var value = 0;
  return () => '$prefix-${++value}';
}

class SocketExceptionForTest implements Exception {
  const SocketExceptionForTest(this.message);

  final String message;

  @override
  String toString() => 'SocketException: $message';
}
