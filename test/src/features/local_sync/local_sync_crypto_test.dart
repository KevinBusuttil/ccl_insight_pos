import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_crypto.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_models.dart';

void main() {
  test('device keys survive secure-store reload', () async {
    final store = InMemoryLocalSyncSecureStore();
    final manager = LocalSyncKeyManager(secureStore: store);

    final created = await manager.loadOrCreateFirstDeviceKeys(
      businessId: 'business-1',
      deviceId: 'device-a',
    );
    final loaded = await manager.load(
      businessId: 'business-1',
      deviceId: 'device-a',
      keyEpoch: 1,
    );

    expect(loaded, isNotNull);
    expect(loaded!.signingPrivateKey, created.signingPrivateKey);
    expect(loaded.signingPublicKey, created.signingPublicKey);
    expect(loaded.exchangePrivateKey, created.exchangePrivateKey);
    expect(loaded.businessKey, created.businessKey);
    expect(store.values.keys, isNotEmpty);
  });

  test(
    'encrypted envelope verifies and rejects ciphertext tampering',
    () async {
      final manager = LocalSyncKeyManager(
        secureStore: InMemoryLocalSyncSecureStore(),
      );
      final keys = await manager.loadOrCreateFirstDeviceKeys(
        businessId: 'business-1',
        deviceId: 'device-a',
      );
      const profile = LocalSyncProfile(
        businessId: 'business-1',
        shopId: 'shop-a',
        shopName: 'Shop A',
        deviceId: 'device-a',
        deviceName: 'Till A',
        relayUrl: 'wss://relay.invalid',
        protocolVersion: 1,
        keyEpoch: 1,
      );
      final crypto = LocalSyncCrypto();
      final envelope = await crypto.encryptAndSign(
        profile: profile,
        keys: keys,
        eventId: 'event-1',
        entityType: LocalSyncEntityType.customer,
        entityId: 'customer-1',
        operation: LocalSyncOperation.upsert,
        hlc: '1000:0:device-a',
        payload: const <String, Object?>{
          'customer': <String, Object?>{'name': 'customer-1'},
        },
        createdAt: DateTime.utc(2026, 9, 21, 12),
      );

      final clearPayload = await crypto.verifyAndDecrypt(
        envelope: envelope,
        signingPublicKey: keys.signingPublicKey,
        businessKey: keys.businessKey,
      );
      expect((clearPayload['customer'] as Map)['name'], 'customer-1');

      final tamperedJson = Map<String, dynamic>.from(envelope.toJson());
      final cipherBytes = base64Decode('${tamperedJson['ciphertext']}');
      cipherBytes[0] ^= 1;
      tamperedJson['ciphertext'] = base64Encode(cipherBytes);
      final tampered = LocalSyncEnvelope.fromJson(tamperedJson);

      await expectLater(
        crypto.verifyAndDecrypt(
          envelope: tampered,
          signingPublicKey: keys.signingPublicKey,
          businessKey: keys.businessKey,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'trusted device wraps the business key for a pending register',
    () async {
      final approverManager = LocalSyncKeyManager(
        secureStore: InMemoryLocalSyncSecureStore(),
      );
      final pendingStore = InMemoryLocalSyncSecureStore();
      final pendingManager = LocalSyncKeyManager(secureStore: pendingStore);
      final approverKeys = await approverManager.loadOrCreateFirstDeviceKeys(
        businessId: 'business-1',
        deviceId: 'device-a',
      );
      final pendingKeys = await pendingManager.loadOrCreateEnrollmentKeys(
        businessId: 'business-1',
        deviceId: 'device-b',
      );
      final crypto = LocalSyncCrypto();

      final envelope = await crypto.wrapBusinessKeyForEnrollment(
        approverKeys: approverKeys,
        businessId: 'business-1',
        enrollmentId: 'enrollment-1',
        targetDeviceId: 'device-b',
        targetExchangePublicKey: pendingKeys.exchangePublicKey,
      );
      final unwrapped = await crypto.unwrapBusinessKeyFromEnrollment(
        enrollmentKeys: pendingKeys,
        encryptedEnvelope: envelope,
        businessId: 'business-1',
        enrollmentId: 'enrollment-1',
        targetDeviceId: 'device-b',
      );
      final completed = await pendingManager.completeEnrollment(
        businessId: 'business-1',
        deviceId: 'device-b',
        keyEpoch: unwrapped.keyEpoch,
        businessKey: unwrapped.businessKey,
      );

      expect(completed.businessKey, approverKeys.businessKey);
      expect(completed.signingPublicKey, pendingKeys.signingPublicKey);
      expect(
        await pendingManager.loadEnrollmentKeys(
          businessId: 'business-1',
          deviceId: 'device-b',
        ),
        isNull,
      );
    },
  );
}
