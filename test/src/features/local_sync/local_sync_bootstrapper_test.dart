import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/local_sync_repository.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_bootstrapper.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'registers the first device and restores its coordinator offline',
    () async {
      sqfliteFfiInit();
      final databasePath = path.join(
        await databaseFactoryFfi.getDatabasesPath(),
        'neuradix_local_sync_bootstrapper.db',
      );
      await databaseFactoryFfi.deleteDatabase(databasePath);
      final databaseOwner = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final database = await databaseOwner.open();
      final repository = LocalSyncRepository(database);
      final secureStore = InMemoryLocalSyncSecureStore();
      var registered = false;

      Map<String, dynamic> metadata({
        required List<Map<String, Object?>> devices,
      }) {
        return <String, dynamic>{
          'business_id': 'NBIZ-00001',
          'metadata_only': true,
          'relay_url': 'wss://relay.neuradix.test',
          'protocol_version': 1,
          'shop': <String, Object?>{'name': 'SHOP-1', 'shop_name': 'ABP Main'},
          'shops': <Map<String, Object?>>[
            <String, Object?>{'name': 'SHOP-1', 'shop_name': 'ABP Main'},
          ],
          'devices': devices,
        };
      }

      final bootstrapper = LocalSyncBootstrapper(
        repository: repository,
        keyManager: LocalSyncKeyManager(secureStore: secureStore),
        fetchMetadata:
            () async => metadata(devices: const <Map<String, Object?>>[]),
        registerFirstDevice: (LocalSyncDeviceKeys keys) async {
          registered = true;
          return metadata(
            devices: <Map<String, Object?>>[
              <String, Object?>{
                'device_id': 'device-1',
                'device_name': 'Main Till',
                'shop': 'SHOP-1',
                'shop_name': 'ABP Main',
                'status': 'active',
                'signing_public_key': keys.signingPublicKeyBase64,
                'exchange_public_key': keys.exchangePublicKeyBase64,
                'key_epoch': 1,
                'is_preferred_peer': 1,
              },
            ],
          );
        },
      );

      final firstResult = await bootstrapper.bootstrap(
        businessId: 'NBIZ-00001',
        deviceId: 'device-1',
        deviceName: 'Main Till',
        fallbackRelayUrl: '',
        fallbackProtocolVersion: 1,
      );

      expect(registered, isTrue);
      expect(firstResult.status, 'ready');
      expect(firstResult.coordinator, isNotNull);
      expect(firstResult.profile?.shopId, 'SHOP-1');
      expect(
        (await repository.readProfile())?.relayUrl,
        'wss://relay.neuradix.test',
      );

      final offlineBootstrapper = LocalSyncBootstrapper(
        repository: repository,
        keyManager: LocalSyncKeyManager(secureStore: secureStore),
        fetchMetadata:
            () => Future<Map<String, dynamic>>.error(StateError('offline')),
        registerFirstDevice:
            (_) => throw StateError('must not register offline'),
      );
      final offlineResult = await offlineBootstrapper.bootstrap(
        businessId: 'NBIZ-00001',
        deviceId: 'device-1',
        deviceName: 'Main Till',
        fallbackRelayUrl: '',
        fallbackProtocolVersion: 1,
      );

      expect(offlineResult.status, 'offline');
      expect(offlineResult.coordinator, isNotNull);

      await databaseOwner.close();
      await databaseFactoryFfi.deleteDatabase(databasePath);
    },
  );

  test(
    'requires trusted-device enrollment when another device already exists',
    () async {
      sqfliteFfiInit();
      final databasePath = path.join(
        await databaseFactoryFfi.getDatabasesPath(),
        'neuradix_local_sync_pairing_required.db',
      );
      await databaseFactoryFfi.deleteDatabase(databasePath);
      final databaseOwner = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final database = await databaseOwner.open();
      final bootstrapper = LocalSyncBootstrapper(
        repository: LocalSyncRepository(database),
        keyManager: LocalSyncKeyManager(
          secureStore: InMemoryLocalSyncSecureStore(),
        ),
        fetchMetadata:
            () async => <String, dynamic>{
              'business_id': 'NBIZ-00001',
              'relay_url': 'wss://relay.neuradix.test',
              'protocol_version': 1,
              'devices': <Map<String, Object?>>[
                <String, Object?>{
                  'device_id': 'trusted-device',
                  'status': 'active',
                },
              ],
            },
        registerFirstDevice: (_) => throw StateError('must not self-register'),
      );

      final result = await bootstrapper.bootstrap(
        businessId: 'NBIZ-00001',
        deviceId: 'new-device',
        deviceName: 'New Till',
        fallbackRelayUrl: '',
        fallbackProtocolVersion: 1,
      );

      expect(result.status, 'enrollment_required');
      expect(result.coordinator, isNull);
      await databaseOwner.close();
      await databaseFactoryFfi.deleteDatabase(databasePath);
    },
  );

  test('starts a trusted-device enrollment for a second register', () async {
    sqfliteFfiInit();
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'neuradix_local_sync_pairing_started.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);
    final databaseOwner = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final database = await databaseOwner.open();
    LocalSyncEnrollmentKeys? submittedKeys;
    final bootstrapper = LocalSyncBootstrapper(
      repository: LocalSyncRepository(database),
      keyManager: LocalSyncKeyManager(
        secureStore: InMemoryLocalSyncSecureStore(),
      ),
      fetchMetadata:
          () async => <String, dynamic>{
            'business_id': 'NBIZ-00001',
            'relay_url': 'wss://relay.neuradix.test',
            'protocol_version': 1,
            'devices': <Map<String, Object?>>[
              <String, Object?>{
                'device_id': 'trusted-device',
                'status': 'active',
              },
            ],
          },
      registerFirstDevice: (_) => throw StateError('must not self-register'),
      startEnrollment: (LocalSyncEnrollmentKeys keys) async {
        submittedKeys = keys;
        return <String, dynamic>{
          'enrollment': <String, Object?>{'name': 'ENROLL-1'},
          'qr_payload': <String, Object?>{
            'business_id': 'NBIZ-00001',
            'enrollment_id': 'ENROLL-1',
            'device_id': 'new-device',
            'exchange_public_key': keys.exchangePublicKeyBase64,
          },
        };
      },
    );

    final result = await bootstrapper.bootstrap(
      businessId: 'NBIZ-00001',
      deviceId: 'new-device',
      deviceName: 'New Till',
      fallbackRelayUrl: '',
      fallbackProtocolVersion: 1,
    );

    expect(result.status, 'enrollment_pending');
    expect(result.enrollmentId, 'ENROLL-1');
    expect(result.pairingPayload['device_id'], 'new-device');
    expect(submittedKeys, isNotNull);
    await databaseOwner.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });
}
