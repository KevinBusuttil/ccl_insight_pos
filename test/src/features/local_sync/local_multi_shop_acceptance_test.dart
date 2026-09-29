import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/hosted_local_repository.dart';
import 'package:neuradix_pos/src/data/local/local_sync_repository.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/hosted/hosted_models.dart';
import 'package:neuradix_pos/src/features/local_sync/hybrid_logical_clock.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_coordinator.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_crypto.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_models.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'two shops converge customers and 18 finalized sales without sharing inventory',
    () async {
      sqfliteFfiInit();
      final shopA = await _TestRegister.create(
        deviceId: 'register-a',
        shopId: 'shop-a',
        shopName: 'ABP Shop A',
      );
      final shopB = await _TestRegister.create(
        deviceId: 'register-b',
        shopId: 'shop-b',
        shopName: 'ABP Shop B',
        businessKey: shopA.keys.businessKey,
      );
      addTearDown(() async {
        await shopA.dispose();
        await shopB.dispose();
      });
      await shopA.trust(shopB);
      await shopB.trust(shopA);

      final inventoryA = await _createInventory(shopA, 'A');
      final inventoryB = await _createInventory(shopB, 'B');
      final firstShopAItemEvent =
          (await shopA.repository.readPendingEvents()).first.envelope;
      await _flush(shopA, shopB);
      await _flush(shopB, shopA);

      expect(await shopA.hosted.listInventoryItems(), hasLength(4));
      expect(await shopB.hosted.listInventoryItems(), hasLength(4));
      expect(
        (await shopA.hosted.listInventoryItems()).map((item) => item.sku),
        everyElement(startsWith('A-')),
      );
      expect(
        (await shopB.hosted.listInventoryItems()).map((item) => item.sku),
        everyElement(startsWith('B-')),
      );

      // Defense in depth: even if a relay incorrectly forwards a shop-local
      // event, the receiving repository must not materialize it.
      final ignored = await shopB.coordinator.applyEnvelope(
        firstShopAItemEvent,
      );
      expect(ignored.status, 'ignored_shop_scope');
      expect(await shopB.hosted.listInventoryItems(), hasLength(4));

      final customersA = await _createCustomers(shopA, 'A');
      final customersB = await _createCustomers(shopB, 'B');
      await _createSales(
        shopA,
        stage: 'offline',
        count: 3,
        customers: customersA,
        inventory: inventoryA,
      );
      await _createSales(
        shopB,
        stage: 'offline',
        count: 3,
        customers: customersB,
        inventory: inventoryB,
      );
      expect(await shopA.repository.pendingEventCount(), 6);
      expect(await shopB.repository.pendingEventCount(), 6);

      // A process/device restart must not lose the encrypted outbox.
      await shopA.restart();
      expect(await shopA.repository.pendingEventCount(), 6);
      await shopA.trust(shopB);
      await _flush(shopA, shopB);
      await _flush(shopB, shopA);
      await _expectConverged(shopA, shopB, sales: 6, customers: 6);

      final onlineA = await _createSales(
        shopA,
        stage: 'online',
        count: 3,
        customers: customersA,
        inventory: inventoryA,
      );
      await _createSales(
        shopB,
        stage: 'online',
        count: 3,
        customers: customersB,
        inventory: inventoryB,
      );
      final deliveredFromA = await _flush(shopA, shopB);
      await _flush(shopB, shopA);
      await _expectConverged(shopA, shopB, sales: 12, customers: 6);

      // Replayed frames are idempotent and cannot duplicate sale lines.
      final duplicateEnvelope = deliveredFromA.firstWhere(
        (event) => event.entityId == onlineA.first.saleId,
      );
      final duplicate = await shopB.coordinator.applyEnvelope(
        duplicateEnvelope,
      );
      expect(duplicate.status, 'duplicate');
      expect(await shopB.hosted.listSales(), hasLength(12));

      // Shop A is offline while Shop B remains attached to the stateless relay.
      await _createSales(
        shopA,
        stage: 'mixed',
        count: 3,
        customers: customersA,
        inventory: inventoryA,
      );
      await _createSales(
        shopB,
        stage: 'mixed',
        count: 3,
        customers: customersB,
        inventory: inventoryB,
      );
      await _flush(shopB, shopA, targetOnline: false);
      expect(await shopB.repository.pendingEventCount(), 3);

      // Restart the online source while its peer is absent. Sent events remain
      // replayable because acknowledgement, not transmission, settles them.
      await shopB.restart();
      expect(await shopB.repository.pendingEventCount(), 3);
      await shopB.trust(shopA);
      await _flush(shopA, shopB);
      await _flush(shopB, shopA);
      await _expectConverged(shopA, shopB, sales: 18, customers: 6);

      // Smaller reverse-direction check: each side edits a different shared
      // customer while Shop B is offline, then both changes converge.
      await shopA.coordinator.saveCustomer(
        customersA.first.copyWith(primaryAddress: 'Updated by Shop A'),
      );
      await shopB.coordinator.saveCustomer(
        customersB.first.copyWith(primaryAddress: 'Updated by Shop B'),
      );
      await _flush(shopA, shopB, targetOnline: false);
      expect(await shopA.repository.pendingEventCount(), 1);
      await _flush(shopA, shopB);
      await _flush(shopB, shopA);
      await _expectConverged(shopA, shopB, sales: 18, customers: 6);
      final customerMapA = <String, HostedCustomer>{
        for (final customer in await shopA.hosted.listCustomers())
          customer.customerId: customer,
      };
      final customerMapB = <String, HostedCustomer>{
        for (final customer in await shopB.hosted.listCustomers())
          customer.customerId: customer,
      };
      expect(
        customerMapA[customersA.first.customerId]?.primaryAddress,
        'Updated by Shop A',
      );
      expect(
        customerMapB[customersB.first.customerId]?.primaryAddress,
        'Updated by Shop B',
      );

      expect(
        shopA.coordinator.saveFinalizedSale(
          _sale(
            shopA,
            id: 'parked-sale',
            customer: customersA.first,
            item: inventoryA.first,
            status: 'parked',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        shopB.coordinator.applyEnvelope(
          _copyEnvelope(duplicateEnvelope, businessId: 'another-business'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await shopA.repository.pendingEventCount(), 0);
      expect(await shopB.repository.pendingEventCount(), 0);
      expect(await shopA.repository.lastSuccessfulSyncAt(), isNotNull);
      expect(await shopB.repository.lastSuccessfulSyncAt(), isNotNull);
    },
  );
}

Future<List<HostedInventoryItem>> _createInventory(
  _TestRegister register,
  String prefix,
) async {
  final items = List<HostedInventoryItem>.generate(
    4,
    (index) => HostedInventoryItem(
      itemId: '${register.profile.shopId}-item-${index + 1}',
      sku: '$prefix-${index + 1}',
      barcode: '535300${prefix.codeUnitAt(0)}${index + 1}',
      displayName: '$prefix Shop Item ${index + 1}',
      imageUrl: '/local/$prefix-${index + 1}.png',
      price: 2.5 + index,
      stockQty: 100.0 - index,
      isActive: true,
    ),
  );
  for (final item in items) {
    await register.coordinator.saveInventoryItem(item);
  }
  return items;
}

Future<List<HostedCustomer>> _createCustomers(
  _TestRegister register,
  String prefix,
) async {
  final customers = List<HostedCustomer>.generate(
    3,
    (index) => HostedCustomer(
      customerId: '$prefix-customer-${index + 1}',
      customerCode: '$prefix-C${index + 1}',
      displayName: '$prefix Customer ${index + 1}',
      mobileNo: '9900${prefix.codeUnitAt(0)}${index + 1}',
      emailId: '${prefix.toLowerCase()}${index + 1}@example.test',
      primaryAddress: '$prefix Address ${index + 1}',
      isActive: true,
    ),
  );
  for (final customer in customers) {
    await register.coordinator.saveCustomer(customer);
  }
  return customers;
}

Future<List<HostedSaleRecord>> _createSales(
  _TestRegister register, {
  required String stage,
  required int count,
  required List<HostedCustomer> customers,
  required List<HostedInventoryItem> inventory,
}) async {
  final sales = <HostedSaleRecord>[];
  for (var index = 0; index < count; index += 1) {
    final sale = _sale(
      register,
      id: '${register.profile.deviceId}-$stage-sale-${index + 1}',
      customer: customers[index % customers.length],
      item: inventory[index % inventory.length],
    );
    await register.coordinator.saveFinalizedSale(sale);
    sales.add(sale);
  }
  return sales;
}

HostedSaleRecord _sale(
  _TestRegister register, {
  required String id,
  required HostedCustomer customer,
  required HostedInventoryItem item,
  String status = 'local_only',
}) {
  final line = HostedSaleLine(
    itemId: item.itemId,
    sku: item.sku,
    barcode: item.barcode,
    displayName: item.displayName,
    qty: 1,
    rate: item.price,
  );
  return HostedSaleRecord(
    saleId: id,
    remoteSaleId: '',
    customerId: customer.customerId,
    customerName: customer.displayName,
    postingDate: '2026-09-29',
    totalAmount: line.amount,
    status: status,
    items: <HostedSaleLine>[line],
  );
}

Future<List<LocalSyncEnvelope>> _flush(
  _TestRegister source,
  _TestRegister target, {
  bool targetOnline = true,
}) async {
  final delivered = <LocalSyncEnvelope>[];
  final pending = await source.repository.readPendingEvents(limit: 1000);
  for (final event in pending) {
    final envelope = event.envelope;
    await source.repository.markSent(envelope.eventId);
    final sameShopInventory =
        envelope.entityType == LocalSyncEntityType.inventoryItem &&
        envelope.shopId == target.profile.shopId;
    final businessWide =
        envelope.entityType != LocalSyncEntityType.inventoryItem;
    if (!targetOnline || (!sameShopInventory && !businessWide)) {
      continue;
    }
    await target.coordinator.applyEnvelope(envelope);
    await source.repository.acknowledge(
      eventId: envelope.eventId,
      peerDeviceId: target.profile.deviceId,
    );
    delivered.add(envelope);
  }
  return delivered;
}

Future<void> _expectConverged(
  _TestRegister shopA,
  _TestRegister shopB, {
  required int sales,
  required int customers,
}) async {
  final salesA = await shopA.hosted.listSales();
  final salesB = await shopB.hosted.listSales();
  expect(salesA, hasLength(sales));
  expect(salesB, hasLength(sales));
  expect(
    salesA.map((sale) => sale.saleId).toSet(),
    salesB.map((sale) => sale.saleId).toSet(),
  );
  expect(salesA.every((sale) => sale.items.length == 1), isTrue);
  expect(salesB.every((sale) => sale.items.length == 1), isTrue);

  final customersA = await shopA.hosted.listCustomers();
  final customersB = await shopB.hosted.listCustomers();
  expect(customersA, hasLength(customers));
  expect(customersB, hasLength(customers));
  expect(
    customersA.map((customer) => customer.customerId).toSet(),
    customersB.map((customer) => customer.customerId).toSet(),
  );

  expect(await shopA.hosted.listInventoryItems(), hasLength(4));
  expect(await shopB.hosted.listInventoryItems(), hasLength(4));
  expect(
    (await shopA.hosted.listInventoryItems())
        .map((item) => item.itemId)
        .toSet(),
    isNot(
      (await shopB.hosted.listInventoryItems())
          .map((item) => item.itemId)
          .toSet(),
    ),
  );
}

LocalSyncEnvelope _copyEnvelope(
  LocalSyncEnvelope envelope, {
  required String businessId,
}) {
  return LocalSyncEnvelope(
    protocolVersion: envelope.protocolVersion,
    eventId: envelope.eventId,
    businessId: businessId,
    shopId: envelope.shopId,
    originDeviceId: envelope.originDeviceId,
    entityType: envelope.entityType,
    entityId: envelope.entityId,
    operation: envelope.operation,
    hlc: envelope.hlc,
    keyEpoch: envelope.keyEpoch,
    createdAt: envelope.createdAt,
    nonce: envelope.nonce,
    ciphertext: envelope.ciphertext,
    mac: envelope.mac,
    signature: envelope.signature,
  );
}

class _TestRegister {
  _TestRegister({
    required this.databasePath,
    required this.profile,
    required this.keys,
    required this.databaseOwner,
    required this.repository,
    required this.hosted,
    required this.coordinator,
  });

  final String databasePath;
  final LocalSyncProfile profile;
  final LocalSyncDeviceKeys keys;
  NeuradixDatabase databaseOwner;
  LocalSyncRepository repository;
  HostedLocalRepository hosted;
  LocalSyncCoordinator coordinator;
  int _eventSequence = 0;

  static Future<_TestRegister> create({
    required String deviceId,
    required String shopId,
    required String shopName,
    List<int>? businessKey,
  }) async {
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'acceptance-$deviceId.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);
    final profile = LocalSyncProfile(
      businessId: 'business-abp',
      shopId: shopId,
      shopName: shopName,
      deviceId: deviceId,
      deviceName: deviceId,
      relayUrl: 'ws://relay.test',
      protocolVersion: 1,
      keyEpoch: 1,
    );
    final generated = await LocalSyncKeyManager(
      secureStore: InMemoryLocalSyncSecureStore(),
    ).loadOrCreateFirstDeviceKeys(
      businessId: profile.businessId,
      deviceId: profile.deviceId,
    );
    final keys = LocalSyncDeviceKeys(
      signingPrivateKey: generated.signingPrivateKey,
      signingPublicKey: generated.signingPublicKey,
      exchangePrivateKey: generated.exchangePrivateKey,
      exchangePublicKey: generated.exchangePublicKey,
      businessKey: businessKey ?? generated.businessKey,
      keyEpoch: 1,
    );
    final owner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final database = await owner.open();
    final repository = LocalSyncRepository(database);
    await repository.saveProfile(profile);
    late final _TestRegister register;
    register = _TestRegister(
      databasePath: databasePath,
      profile: profile,
      keys: keys,
      databaseOwner: owner,
      repository: repository,
      hosted: HostedLocalRepository(database),
      coordinator: LocalSyncCoordinator(
        profile: profile,
        keys: keys,
        repository: repository,
        clock: HybridLogicalClock(nodeId: deviceId),
        eventIdGenerator: () => '$deviceId-event-${++register._eventSequence}',
      ),
    );
    return register;
  }

  Future<void> trust(_TestRegister peer) {
    return repository.upsertPeer(
      deviceId: peer.profile.deviceId,
      shopId: peer.profile.shopId,
      deviceName: peer.profile.deviceName,
      signingPublicKey: peer.keys.signingPublicKeyBase64,
      exchangePublicKey: peer.keys.exchangePublicKeyBase64,
      status: 'active',
      keyEpoch: peer.keys.keyEpoch,
    );
  }

  Future<void> restart() async {
    await databaseOwner.close();
    databaseOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final database = await databaseOwner.open();
    repository = LocalSyncRepository(database);
    hosted = HostedLocalRepository(database);
    coordinator = LocalSyncCoordinator(
      profile: profile,
      keys: keys,
      repository: repository,
      clock: HybridLogicalClock(nodeId: profile.deviceId),
      eventIdGenerator: () => '${profile.deviceId}-event-${++_eventSequence}',
    );
  }

  Future<void> dispose() async {
    await databaseOwner.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  }
}
