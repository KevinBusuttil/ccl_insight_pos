import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/hosted_local_repository.dart';
import 'package:neuradix_pos/src/data/local/local_sync_repository.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/hosted/hosted_models.dart';
import 'package:neuradix_pos/src/features/local_sync/hybrid_logical_clock.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_coordinator.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_crypto.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_models.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_relay_worker.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes a local relay URL for Android emulators', () {
    expect(
      normalizeLocalSyncRelayUrlForRuntime(
        'ws://127.0.0.1:8787',
        platform: TargetPlatform.android,
        isWeb: false,
      ),
      'ws://10.0.2.2:8787',
    );
  });

  test(
    'offline guidance is actionable and does not expose transport details',
    () {
      expect(localSyncOfflineMessage, contains('Changes stay queued'));
      expect(localSyncOfflineMessage, contains('trusted register'));
      expect(localSyncOfflineMessage, contains('retries automatically'));
      expect(localSyncOfflineMessage, isNot(contains('http://')));
      expect(localSyncOfflineMessage, isNot(contains('SocketException')));
    },
  );

  test('durably applies an event before acknowledging its origin', () async {
    final fixture = await _RelayFixture.create('relay_worker_receiver.db');
    final socket = _FakeRelaySocket();
    var changed = false;
    final worker = LocalSyncRelayWorker(
      coordinator: fixture.receiverCoordinator,
      issueToken:
          () async => <String, dynamic>{
            'relay_url': 'ws://relay.test',
            'token': 'token',
          },
      refreshMetadata: () async => fixture.metadata,
      connector: (_) async => socket,
      periodicInterval: const Duration(hours: 1),
      onDataChanged: () {
        changed = true;
      },
    );
    await worker.start();
    final envelope = await fixture.sourceCrypto.encryptAndSign(
      profile: fixture.sourceProfile,
      keys: fixture.sourceKeys,
      eventId: 'inventory-event-1',
      entityType: LocalSyncEntityType.inventoryItem,
      entityId: 'item-1',
      operation: LocalSyncOperation.upsert,
      hlc: '1000:0:device-a',
      payload: <String, Object?>{
        'inventory_item':
            const HostedInventoryItem(
              itemId: 'item-1',
              sku: 'ABP-001',
              barcode: '535300000001',
              displayName: 'Same Shop Item',
              imageUrl: '',
              price: 5,
              stockQty: 3,
              isActive: true,
            ).toApiPayload(),
      },
    );

    socket.add(<String, Object?>{
      'type': 'event',
      'envelope': envelope.toJson(),
    });
    await _waitUntil(() => socket.sent.any((Map row) => row['type'] == 'ack'));

    final inventory = await fixture.hostedRepository.listInventoryItems();
    expect(inventory.single.itemId, 'item-1');
    expect(changed, isTrue);
    final ack = socket.sent.lastWhere((Map row) => row['type'] == 'ack');
    expect(ack['event_id'], 'inventory-event-1');
    expect(ack['peer_device_id'], 'device-b');
    await worker.stop();
    await fixture.dispose();
  });

  test('resends pending events and clears them after peer ack', () async {
    final fixture = await _RelayFixture.create('relay_worker_sender.db');
    final socket = _FakeRelaySocket();
    const customer = HostedCustomer(
      customerId: 'customer-1',
      customerCode: 'ABP-C001',
      displayName: 'Shared Customer',
      mobileNo: '99001122',
      emailId: '',
      primaryAddress: '',
      isActive: true,
    );
    await fixture.sourceCoordinator.saveCustomer(customer);
    final worker = LocalSyncRelayWorker(
      coordinator: fixture.sourceCoordinator,
      issueToken:
          () async => <String, dynamic>{
            'relay_url': 'ws://relay.test',
            'token': 'token',
          },
      refreshMetadata: () async => fixture.metadata,
      connector: (_) async => socket,
      periodicInterval: const Duration(hours: 1),
    );

    await worker.start();
    await _waitUntil(
      () => socket.sent.any((Map row) => row['type'] == 'event'),
    );
    final event = socket.sent.firstWhere((Map row) => row['type'] == 'event');
    final envelope = Map<String, dynamic>.from(event['envelope'] as Map);
    socket.add(<String, Object?>{
      'type': 'ack',
      'event_id': envelope['event_id'],
      'origin_device_id': 'device-a',
      'peer_device_id': 'device-b',
    });
    await _waitUntil(
      () async => await fixture.sourceRepository.pendingEventCount() == 0,
    );

    expect(await fixture.sourceRepository.pendingEventCount(), 0);
    await worker.stop();
    await fixture.dispose();
  });

  test('forced refresh replaces a half-open relay connection', () async {
    final fixture = await _RelayFixture.create('relay_worker_refresh.db');
    final sockets = <_FakeRelaySocket>[];
    final worker = LocalSyncRelayWorker(
      coordinator: fixture.sourceCoordinator,
      issueToken:
          () async => <String, dynamic>{
            'relay_url': 'ws://relay.test',
            'token': 'token',
          },
      refreshMetadata: () async => fixture.metadata,
      connector: (_) async {
        final socket = _FakeRelaySocket();
        sockets.add(socket);
        return socket;
      },
      periodicInterval: const Duration(hours: 1),
    );

    await worker.start();
    expect(sockets, hasLength(1));
    expect(worker.isConnected, isTrue);

    expect(await worker.reconnectAndFlush(), isTrue);
    expect(sockets, hasLength(2));
    expect(sockets.first.isClosed, isTrue);
    expect(worker.isConnected, isTrue);

    await worker.stop();
    await fixture.dispose();
  });

  test(
    'concurrent refresh requests share one replacement connection',
    () async {
      final fixture = await _RelayFixture.create(
        'relay_worker_concurrent_refresh.db',
      );
      final sockets = <_FakeRelaySocket>[];
      final replacementReady = Completer<void>();
      final worker = LocalSyncRelayWorker(
        coordinator: fixture.sourceCoordinator,
        issueToken:
            () async => <String, dynamic>{
              'relay_url': 'ws://relay.test',
              'token': 'token',
            },
        refreshMetadata: () async => fixture.metadata,
        connector: (_) async {
          if (sockets.isNotEmpty) {
            await replacementReady.future;
          }
          final socket = _FakeRelaySocket();
          sockets.add(socket);
          return socket;
        },
        periodicInterval: const Duration(hours: 1),
      );

      await worker.start();
      final firstRefresh = worker.reconnectAndFlush();
      final secondRefresh = worker.reconnectAndFlush();
      replacementReady.complete();

      expect(await Future.wait(<Future<bool>>[firstRefresh, secondRefresh]), [
        true,
        true,
      ]);
      expect(sockets, hasLength(2));
      expect(sockets.first.isClosed, isTrue);

      await worker.stop();
      await fixture.dispose();
    },
  );

  test('heartbeat timeout reconnects a silent relay socket', () async {
    final fixture = await _RelayFixture.create('relay_worker_heartbeat.db');
    final sockets = <_FakeRelaySocket>[];
    var now = DateTime.utc(2026, 9, 29, 12);
    final worker = LocalSyncRelayWorker(
      coordinator: fixture.sourceCoordinator,
      issueToken:
          () async => <String, dynamic>{
            'relay_url': 'ws://relay.test',
            'token': 'token',
          },
      refreshMetadata: () async => fixture.metadata,
      connector: (_) async {
        final socket = _FakeRelaySocket();
        sockets.add(socket);
        return socket;
      },
      periodicInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(seconds: 10),
      heartbeatTimeout: const Duration(seconds: 30),
      metadataRefreshInterval: const Duration(hours: 1),
      clock: () => now,
    );

    await worker.start();
    expect(
      sockets.single.sent.any(
        (Map<String, dynamic> frame) => frame['type'] == 'ping',
      ),
      isTrue,
    );

    now = now.add(const Duration(seconds: 31));
    await worker.runMaintenanceCycle();

    expect(sockets, hasLength(2));
    expect(sockets.first.isClosed, isTrue);
    expect(worker.isConnected, isTrue);

    await worker.stop();
    await fixture.dispose();
  });

  test('tracks online peers from relay hello and peer-state frames', () async {
    final fixture = await _RelayFixture.create('relay_worker_peers.db');
    final socket = _FakeRelaySocket();
    final worker = LocalSyncRelayWorker(
      coordinator: fixture.sourceCoordinator,
      issueToken:
          () async => <String, dynamic>{
            'relay_url': 'ws://relay.test',
            'token': 'token',
          },
      refreshMetadata: () async => fixture.metadata,
      connector: (_) async => socket,
      periodicInterval: const Duration(hours: 1),
    );

    await worker.start();
    socket.add(<String, Object?>{
      'type': 'hello',
      'online_devices': <String>['device-a', 'device-b'],
    });
    await _waitUntil(() => worker.onlinePeerCount == 1);

    socket.add(<String, Object?>{
      'type': 'peer_state',
      'device_id': 'device-b',
      'online': false,
    });
    await _waitUntil(() => worker.onlinePeerCount == 0);

    await worker.stop();
    await fixture.dispose();
  });
}

class _FakeRelaySocket implements LocalSyncRelaySocket {
  final StreamController<Object?> _controller = StreamController<Object?>();
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];

  bool get isClosed => _controller.isClosed;

  @override
  Stream<Object?> get messages => _controller.stream;

  void add(Map<String, Object?> frame) => _controller.add(jsonEncode(frame));

  @override
  void send(String frame) {
    sent.add(Map<String, dynamic>.from(jsonDecode(frame) as Map));
  }

  @override
  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class _RelayFixture {
  _RelayFixture({
    required this.databaseOwner,
    required this.databasePath,
    required this.sourceRepository,
    required this.hostedRepository,
    required this.sourceProfile,
    required this.receiverProfile,
    required this.sourceKeys,
    required this.sourceCoordinator,
    required this.receiverCoordinator,
  });

  final NeuradixDatabase databaseOwner;
  final String databasePath;
  final LocalSyncRepository sourceRepository;
  final HostedLocalRepository hostedRepository;
  final LocalSyncProfile sourceProfile;
  final LocalSyncProfile receiverProfile;
  final LocalSyncDeviceKeys sourceKeys;
  final LocalSyncCoordinator sourceCoordinator;
  final LocalSyncCoordinator receiverCoordinator;
  final LocalSyncCrypto sourceCrypto = LocalSyncCrypto();

  Map<String, dynamic> get metadata => <String, dynamic>{
    'devices': <Map<String, Object?>>[
      <String, Object?>{
        'device_id': sourceProfile.deviceId,
        'device_name': sourceProfile.deviceName,
        'shop': sourceProfile.shopId,
        'signing_public_key': sourceKeys.signingPublicKeyBase64,
        'exchange_public_key': sourceKeys.exchangePublicKeyBase64,
        'status': 'active',
        'key_epoch': 1,
      },
      <String, Object?>{
        'device_id': receiverProfile.deviceId,
        'device_name': receiverProfile.deviceName,
        'shop': receiverProfile.shopId,
        'signing_public_key': receiverCoordinator.keys.signingPublicKeyBase64,
        'exchange_public_key': receiverCoordinator.keys.exchangePublicKeyBase64,
        'status': 'active',
        'key_epoch': 1,
      },
    ],
  };

  static Future<_RelayFixture> create(String fileName) async {
    sqfliteFfiInit();
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      fileName,
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);
    final databaseOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final database = await databaseOwner.open();
    final repository = LocalSyncRepository(database);
    const sourceProfile = LocalSyncProfile(
      businessId: 'business-abp',
      shopId: 'shop-1',
      shopName: 'ABP Shop 1',
      deviceId: 'device-a',
      deviceName: 'Till A',
      relayUrl: 'ws://relay.test',
      protocolVersion: 1,
      keyEpoch: 1,
    );
    const receiverProfile = LocalSyncProfile(
      businessId: 'business-abp',
      shopId: 'shop-1',
      shopName: 'ABP Shop 1',
      deviceId: 'device-b',
      deviceName: 'Till B',
      relayUrl: 'ws://relay.test',
      protocolVersion: 1,
      keyEpoch: 1,
    );
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
    await repository.saveProfile(sourceProfile);
    await repository.upsertPeer(
      deviceId: receiverProfile.deviceId,
      shopId: receiverProfile.shopId,
      deviceName: receiverProfile.deviceName,
      signingPublicKey: receiverKeys.signingPublicKeyBase64,
      exchangePublicKey: receiverKeys.exchangePublicKeyBase64,
      status: 'active',
      keyEpoch: 1,
    );
    final sourceCoordinator = LocalSyncCoordinator(
      profile: sourceProfile,
      keys: sourceKeys,
      repository: repository,
      clock: HybridLogicalClock(nodeId: sourceProfile.deviceId),
    );

    final receiverDatabasePath = '$databasePath.receiver';
    await databaseFactoryFfi.deleteDatabase(receiverDatabasePath);
    final receiverOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: receiverDatabasePath,
    );
    final receiverDatabase = await receiverOwner.open();
    final receiverRepository = LocalSyncRepository(receiverDatabase);
    await receiverRepository.saveProfile(receiverProfile);
    await receiverRepository.upsertPeer(
      deviceId: sourceProfile.deviceId,
      shopId: sourceProfile.shopId,
      deviceName: sourceProfile.deviceName,
      signingPublicKey: sourceKeys.signingPublicKeyBase64,
      exchangePublicKey: sourceKeys.exchangePublicKeyBase64,
      status: 'active',
      keyEpoch: 1,
    );
    final receiverCoordinator = LocalSyncCoordinator(
      profile: receiverProfile,
      keys: receiverKeys,
      repository: receiverRepository,
      clock: HybridLogicalClock(nodeId: receiverProfile.deviceId),
    );
    return _RelayFixture(
      databaseOwner: _CombinedDatabaseOwner(databaseOwner, receiverOwner),
      databasePath: databasePath,
      sourceRepository: repository,
      hostedRepository: HostedLocalRepository(receiverDatabase),
      sourceProfile: sourceProfile,
      receiverProfile: receiverProfile,
      sourceKeys: sourceKeys,
      sourceCoordinator: sourceCoordinator,
      receiverCoordinator: receiverCoordinator,
    );
  }

  Future<void> dispose() async {
    await databaseOwner.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
    await databaseFactoryFfi.deleteDatabase('$databasePath.receiver');
  }
}

class _CombinedDatabaseOwner extends NeuradixDatabase {
  _CombinedDatabaseOwner(this.first, this.second);

  final NeuradixDatabase first;
  final NeuradixDatabase second;

  @override
  Future<void> close() async {
    await first.close();
    await second.close();
  }
}

Future<void> _waitUntil(FutureOr<bool> Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met before timeout.');
}
