import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_sync_models.dart';

class LocalSyncDeviceKeys {
  const LocalSyncDeviceKeys({
    required this.signingPrivateKey,
    required this.signingPublicKey,
    required this.exchangePrivateKey,
    required this.exchangePublicKey,
    required this.businessKey,
    required this.keyEpoch,
  });

  final List<int> signingPrivateKey;
  final List<int> signingPublicKey;
  final List<int> exchangePrivateKey;
  final List<int> exchangePublicKey;
  final List<int> businessKey;
  final int keyEpoch;

  KeyPair get signingKeyPair => SimpleKeyPairData(
    signingPrivateKey,
    publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519),
    type: KeyPairType.ed25519,
  );

  KeyPair get exchangeKeyPair => SimpleKeyPairData(
    exchangePrivateKey,
    publicKey: SimplePublicKey(exchangePublicKey, type: KeyPairType.x25519),
    type: KeyPairType.x25519,
  );

  String get signingPublicKeyBase64 => base64Encode(signingPublicKey);
  String get exchangePublicKeyBase64 => base64Encode(exchangePublicKey);
}

class LocalSyncEnrollmentKeys {
  const LocalSyncEnrollmentKeys({
    required this.signingPrivateKey,
    required this.signingPublicKey,
    required this.exchangePrivateKey,
    required this.exchangePublicKey,
  });

  final List<int> signingPrivateKey;
  final List<int> signingPublicKey;
  final List<int> exchangePrivateKey;
  final List<int> exchangePublicKey;

  String get signingPublicKeyBase64 => base64Encode(signingPublicKey);
  String get exchangePublicKeyBase64 => base64Encode(exchangePublicKey);

  KeyPair get exchangeKeyPair => SimpleKeyPairData(
    exchangePrivateKey,
    publicKey: SimplePublicKey(exchangePublicKey, type: KeyPairType.x25519),
    type: KeyPairType.x25519,
  );
}

abstract class LocalSyncSecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterLocalSyncSecureStore implements LocalSyncSecureStore {
  FlutterLocalSyncSecureStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemoryLocalSyncSecureStore implements LocalSyncSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class LocalSyncKeyManager {
  LocalSyncKeyManager({
    required LocalSyncSecureStore secureStore,
    Cryptography? cryptography,
  }) : _secureStore = secureStore,
       _cryptography = cryptography ?? Cryptography.instance;

  final LocalSyncSecureStore _secureStore;
  final Cryptography _cryptography;

  Future<LocalSyncDeviceKeys> loadOrCreateFirstDeviceKeys({
    required String businessId,
    required String deviceId,
    int keyEpoch = 1,
  }) async {
    final existing = await load(
      businessId: businessId,
      deviceId: deviceId,
      keyEpoch: keyEpoch,
    );
    if (existing != null) {
      return existing;
    }

    final signingKeyPair = await _cryptography.ed25519().newKeyPair();
    final exchangeKeyPair = await _cryptography.x25519().newKeyPair();
    final businessKey = await _cryptography.aesGcm().newSecretKey();
    final keys = LocalSyncDeviceKeys(
      signingPrivateKey: await signingKeyPair.extractPrivateKeyBytes(),
      signingPublicKey: (await signingKeyPair.extractPublicKey()).bytes,
      exchangePrivateKey: await exchangeKeyPair.extractPrivateKeyBytes(),
      exchangePublicKey: (await exchangeKeyPair.extractPublicKey()).bytes,
      businessKey: await businessKey.extractBytes(),
      keyEpoch: keyEpoch,
    );
    await save(businessId: businessId, deviceId: deviceId, keys: keys);
    return keys;
  }

  Future<void> save({
    required String businessId,
    required String deviceId,
    required LocalSyncDeviceKeys keys,
  }) async {
    final prefix = _prefix(businessId, deviceId, keys.keyEpoch);
    await Future.wait(<Future<void>>[
      _secureStore.write(
        '$prefix.signing_private',
        base64Encode(keys.signingPrivateKey),
      ),
      _secureStore.write(
        '$prefix.signing_public',
        base64Encode(keys.signingPublicKey),
      ),
      _secureStore.write(
        '$prefix.exchange_private',
        base64Encode(keys.exchangePrivateKey),
      ),
      _secureStore.write(
        '$prefix.exchange_public',
        base64Encode(keys.exchangePublicKey),
      ),
      _secureStore.write(
        '$prefix.business_key',
        base64Encode(keys.businessKey),
      ),
    ]);
  }

  Future<LocalSyncEnrollmentKeys> loadOrCreateEnrollmentKeys({
    required String businessId,
    required String deviceId,
  }) async {
    final existing = await loadEnrollmentKeys(
      businessId: businessId,
      deviceId: deviceId,
    );
    if (existing != null) {
      return existing;
    }
    final signingKeyPair = await _cryptography.ed25519().newKeyPair();
    final exchangeKeyPair = await _cryptography.x25519().newKeyPair();
    final keys = LocalSyncEnrollmentKeys(
      signingPrivateKey: await signingKeyPair.extractPrivateKeyBytes(),
      signingPublicKey: (await signingKeyPair.extractPublicKey()).bytes,
      exchangePrivateKey: await exchangeKeyPair.extractPrivateKeyBytes(),
      exchangePublicKey: (await exchangeKeyPair.extractPublicKey()).bytes,
    );
    final prefix = _enrollmentPrefix(businessId, deviceId);
    await Future.wait(<Future<void>>[
      _secureStore.write(
        '$prefix.signing_private',
        base64Encode(keys.signingPrivateKey),
      ),
      _secureStore.write(
        '$prefix.signing_public',
        base64Encode(keys.signingPublicKey),
      ),
      _secureStore.write(
        '$prefix.exchange_private',
        base64Encode(keys.exchangePrivateKey),
      ),
      _secureStore.write(
        '$prefix.exchange_public',
        base64Encode(keys.exchangePublicKey),
      ),
    ]);
    return keys;
  }

  Future<LocalSyncEnrollmentKeys?> loadEnrollmentKeys({
    required String businessId,
    required String deviceId,
  }) async {
    final prefix = _enrollmentPrefix(businessId, deviceId);
    final values = await Future.wait<String?>(<Future<String?>>[
      _secureStore.read('$prefix.signing_private'),
      _secureStore.read('$prefix.signing_public'),
      _secureStore.read('$prefix.exchange_private'),
      _secureStore.read('$prefix.exchange_public'),
    ]);
    if (values.any((String? value) => value == null || value.isEmpty)) {
      return null;
    }
    return LocalSyncEnrollmentKeys(
      signingPrivateKey: base64Decode(values[0]!),
      signingPublicKey: base64Decode(values[1]!),
      exchangePrivateKey: base64Decode(values[2]!),
      exchangePublicKey: base64Decode(values[3]!),
    );
  }

  Future<LocalSyncDeviceKeys> completeEnrollment({
    required String businessId,
    required String deviceId,
    required int keyEpoch,
    required List<int> businessKey,
  }) async {
    final pending = await loadEnrollmentKeys(
      businessId: businessId,
      deviceId: deviceId,
    );
    if (pending == null) {
      throw StateError('The pending device enrollment keys are unavailable.');
    }
    final keys = LocalSyncDeviceKeys(
      signingPrivateKey: pending.signingPrivateKey,
      signingPublicKey: pending.signingPublicKey,
      exchangePrivateKey: pending.exchangePrivateKey,
      exchangePublicKey: pending.exchangePublicKey,
      businessKey: businessKey,
      keyEpoch: keyEpoch,
    );
    await save(businessId: businessId, deviceId: deviceId, keys: keys);
    await _deleteEnrollmentKeys(businessId: businessId, deviceId: deviceId);
    return keys;
  }

  Future<LocalSyncDeviceKeys?> load({
    required String businessId,
    required String deviceId,
    required int keyEpoch,
  }) async {
    final prefix = _prefix(businessId, deviceId, keyEpoch);
    final values = await Future.wait<String?>(<Future<String?>>[
      _secureStore.read('$prefix.signing_private'),
      _secureStore.read('$prefix.signing_public'),
      _secureStore.read('$prefix.exchange_private'),
      _secureStore.read('$prefix.exchange_public'),
      _secureStore.read('$prefix.business_key'),
    ]);
    if (values.any((String? value) => value == null || value.isEmpty)) {
      return null;
    }
    return LocalSyncDeviceKeys(
      signingPrivateKey: base64Decode(values[0]!),
      signingPublicKey: base64Decode(values[1]!),
      exchangePrivateKey: base64Decode(values[2]!),
      exchangePublicKey: base64Decode(values[3]!),
      businessKey: base64Decode(values[4]!),
      keyEpoch: keyEpoch,
    );
  }

  String _prefix(String businessId, String deviceId, int keyEpoch) {
    final namespace = base64UrlEncode(utf8.encode('$businessId::$deviceId'));
    return 'neuradix.local_sync.$namespace.epoch_$keyEpoch';
  }

  String _enrollmentPrefix(String businessId, String deviceId) {
    final namespace = base64UrlEncode(utf8.encode('$businessId::$deviceId'));
    return 'neuradix.local_sync.$namespace.enrollment';
  }

  Future<void> _deleteEnrollmentKeys({
    required String businessId,
    required String deviceId,
  }) async {
    final prefix = _enrollmentPrefix(businessId, deviceId);
    await Future.wait(<Future<void>>[
      _secureStore.delete('$prefix.signing_private'),
      _secureStore.delete('$prefix.signing_public'),
      _secureStore.delete('$prefix.exchange_private'),
      _secureStore.delete('$prefix.exchange_public'),
    ]);
  }
}

class LocalSyncCrypto {
  LocalSyncCrypto({Cryptography? cryptography})
    : _cryptography = cryptography ?? Cryptography.instance;

  final Cryptography _cryptography;

  Future<LocalSyncEnvelope> encryptAndSign({
    required LocalSyncProfile profile,
    required LocalSyncDeviceKeys keys,
    required String eventId,
    required LocalSyncEntityType entityType,
    required String entityId,
    required LocalSyncOperation operation,
    required String hlc,
    required Map<String, Object?> payload,
    DateTime? createdAt,
  }) async {
    if (profile.keyEpoch != keys.keyEpoch) {
      throw StateError(
        'The local sync profile and business key epochs differ.',
      );
    }
    final resolvedCreatedAt = (createdAt ?? DateTime.now()).toUtc();
    final header = <String, Object?>{
      'protocol_version': profile.protocolVersion,
      'event_id': eventId,
      'business_id': profile.businessId,
      'shop_id': profile.shopId,
      'origin_device_id': profile.deviceId,
      'entity_type': entityType.value,
      'entity_id': entityId,
      'operation': operation.value,
      'hlc': hlc,
      'key_epoch': keys.keyEpoch,
      'created_at': resolvedCreatedAt.toIso8601String(),
    };
    final cipher = _cryptography.aesGcm();
    final nonce = cipher.newNonce();
    final secretBox = await cipher.encrypt(
      utf8.encode(canonicalJsonEncode(payload)),
      secretKey: SecretKey(keys.businessKey),
      nonce: nonce,
      aad: utf8.encode(canonicalJsonEncode(header)),
    );
    final signedBody = <String, Object?>{
      ...header,
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    final signature = await _cryptography.ed25519().sign(
      utf8.encode(canonicalJsonEncode(signedBody)),
      keyPair: keys.signingKeyPair,
    );
    return LocalSyncEnvelope.fromJson(<String, dynamic>{
      ...signedBody,
      'signature': base64Encode(signature.bytes),
    });
  }

  Future<Map<String, dynamic>> verifyAndDecrypt({
    required LocalSyncEnvelope envelope,
    required List<int> signingPublicKey,
    required List<int> businessKey,
  }) async {
    final isValid = await _cryptography.ed25519().verify(
      utf8.encode(canonicalJsonEncode(envelope.signedBody)),
      signature: Signature(
        base64Decode(envelope.signature),
        publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!isValid) {
      throw const FormatException('The local sync event signature is invalid.');
    }

    final clearBytes = await _cryptography.aesGcm().decrypt(
      SecretBox(
        base64Decode(envelope.ciphertext),
        nonce: base64Decode(envelope.nonce),
        mac: Mac(base64Decode(envelope.mac)),
      ),
      secretKey: SecretKey(businessKey),
      aad: utf8.encode(canonicalJsonEncode(envelope.header)),
    );
    final decoded = jsonDecode(utf8.decode(clearBytes));
    if (decoded is! Map) {
      throw const FormatException('The local sync payload must be an object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<String> wrapBusinessKeyForEnrollment({
    required LocalSyncDeviceKeys approverKeys,
    required String businessId,
    required String enrollmentId,
    required String targetDeviceId,
    required List<int> targetExchangePublicKey,
  }) async {
    final keyEpoch = approverKeys.keyEpoch;
    final wrappingNonce = _cryptography.aesGcm().newNonce();
    final hkdfSalt = _cryptography.aesGcm().newNonce();
    final header = <String, Object?>{
      'version': 1,
      'business_id': businessId,
      'enrollment_id': enrollmentId,
      'target_device_id': targetDeviceId,
      'key_epoch': keyEpoch,
      'approver_exchange_public_key': base64Encode(
        approverKeys.exchangePublicKey,
      ),
      'hkdf_salt': base64Encode(hkdfSalt),
    };
    final sharedSecret = await _cryptography.x25519().sharedSecretKey(
      keyPair: approverKeys.exchangeKeyPair,
      remotePublicKey: SimplePublicKey(
        targetExchangePublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await _deriveEnrollmentWrappingKey(
      sharedSecret: sharedSecret,
      salt: hkdfSalt,
      header: header,
    );
    final secretBox = await _cryptography.aesGcm().encrypt(
      approverKeys.businessKey,
      secretKey: wrappingKey,
      nonce: wrappingNonce,
      aad: utf8.encode(canonicalJsonEncode(header)),
    );
    return canonicalJsonEncode(<String, Object?>{
      ...header,
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<({List<int> businessKey, int keyEpoch})>
  unwrapBusinessKeyFromEnrollment({
    required LocalSyncEnrollmentKeys enrollmentKeys,
    required String encryptedEnvelope,
    required String businessId,
    required String enrollmentId,
    required String targetDeviceId,
  }) async {
    final decoded = jsonDecode(encryptedEnvelope);
    if (decoded is! Map) {
      throw const FormatException('The device key envelope is invalid.');
    }
    final envelope = Map<String, dynamic>.from(decoded);
    if ('${envelope['business_id'] ?? ''}' != businessId ||
        '${envelope['enrollment_id'] ?? ''}' != enrollmentId ||
        '${envelope['target_device_id'] ?? ''}' != targetDeviceId) {
      throw const FormatException(
        'The device key envelope belongs to another enrollment.',
      );
    }
    final keyEpoch = int.tryParse('${envelope['key_epoch']}') ?? 0;
    if (keyEpoch < 1) {
      throw const FormatException('The device key epoch is invalid.');
    }
    final header = <String, Object?>{
      'version': int.tryParse('${envelope['version']}') ?? 0,
      'business_id': businessId,
      'enrollment_id': enrollmentId,
      'target_device_id': targetDeviceId,
      'key_epoch': keyEpoch,
      'approver_exchange_public_key':
          '${envelope['approver_exchange_public_key'] ?? ''}',
      'hkdf_salt': '${envelope['hkdf_salt'] ?? ''}',
    };
    final sharedSecret = await _cryptography.x25519().sharedSecretKey(
      keyPair: enrollmentKeys.exchangeKeyPair,
      remotePublicKey: SimplePublicKey(
        base64Decode('${envelope['approver_exchange_public_key']}'),
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await _deriveEnrollmentWrappingKey(
      sharedSecret: sharedSecret,
      salt: base64Decode('${envelope['hkdf_salt']}'),
      header: header,
    );
    final businessKey = await _cryptography.aesGcm().decrypt(
      SecretBox(
        base64Decode('${envelope['ciphertext']}'),
        nonce: base64Decode('${envelope['nonce']}'),
        mac: Mac(base64Decode('${envelope['mac']}')),
      ),
      secretKey: wrappingKey,
      aad: utf8.encode(canonicalJsonEncode(header)),
    );
    if (businessKey.length != 32) {
      throw const FormatException('The unwrapped business key is invalid.');
    }
    return (businessKey: businessKey, keyEpoch: keyEpoch);
  }

  Future<SecretKey> _deriveEnrollmentWrappingKey({
    required SecretKey sharedSecret,
    required List<int> salt,
    required Map<String, Object?> header,
  }) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode(
        'neuradix-local-sync-enrollment::${canonicalJsonEncode(header)}',
      ),
    );
  }
}
