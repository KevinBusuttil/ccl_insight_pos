import '../../data/local/local_sync_repository.dart';
import 'hybrid_logical_clock.dart';
import 'local_sync_coordinator.dart';
import 'local_sync_crypto.dart';
import 'local_sync_models.dart';

typedef LocalSyncMetadataFetcher = Future<Map<String, dynamic>> Function();
typedef LocalSyncFirstDeviceRegistrar =
    Future<Map<String, dynamic>> Function(LocalSyncDeviceKeys keys);
typedef LocalSyncEnrollmentStarter =
    Future<Map<String, dynamic>> Function(LocalSyncEnrollmentKeys keys);

class LocalSyncBootstrapResult {
  const LocalSyncBootstrapResult({
    required this.status,
    required this.message,
    this.coordinator,
    this.profile,
    this.enrollmentId = '',
    this.pairingPayload = const <String, Object?>{},
  });

  final String status;
  final String message;
  final LocalSyncCoordinator? coordinator;
  final LocalSyncProfile? profile;
  final String enrollmentId;
  final Map<String, Object?> pairingPayload;

  bool get isReady => coordinator != null;
}

class LocalSyncBootstrapper {
  LocalSyncBootstrapper({
    required this.repository,
    required this.keyManager,
    required this.fetchMetadata,
    required this.registerFirstDevice,
    this.startEnrollment,
  });

  final LocalSyncRepository repository;
  final LocalSyncKeyManager keyManager;
  final LocalSyncMetadataFetcher fetchMetadata;
  final LocalSyncFirstDeviceRegistrar registerFirstDevice;
  final LocalSyncEnrollmentStarter? startEnrollment;

  Future<LocalSyncBootstrapResult> bootstrap({
    required String businessId,
    required String deviceId,
    required String deviceName,
    required String fallbackRelayUrl,
    required int fallbackProtocolVersion,
  }) async {
    final restored = await _restoreCoordinator(
      businessId: businessId,
      deviceId: deviceId,
    );

    Map<String, dynamic> metadata;
    try {
      metadata = await fetchMetadata();
    } catch (_) {
      if (restored != null) {
        return LocalSyncBootstrapResult(
          status: 'offline',
          message:
              'Local sync is ready; trust metadata will refresh when online.',
          coordinator: restored,
          profile: restored.profile,
        );
      }
      rethrow;
    }

    final metadataBusinessId = '${metadata['business_id'] ?? ''}';
    if (metadataBusinessId.isNotEmpty && metadataBusinessId != businessId) {
      throw StateError('The local sync metadata belongs to another business.');
    }
    var devices = _mapList(metadata['devices']);
    LocalSyncDeviceKeys? keys;
    if (devices.isEmpty) {
      keys = await keyManager.loadOrCreateFirstDeviceKeys(
        businessId: businessId,
        deviceId: deviceId,
      );
      metadata = await registerFirstDevice(keys);
      devices = _mapList(metadata['devices']);
    }

    final currentDevice = _findDevice(devices, deviceId);
    if (currentDevice == null || '${currentDevice['status']}' != 'active') {
      final enrollmentStarter = startEnrollment;
      if (enrollmentStarter != null) {
        final enrollmentKeys = await keyManager.loadOrCreateEnrollmentKeys(
          businessId: businessId,
          deviceId: deviceId,
        );
        final started = await enrollmentStarter(enrollmentKeys);
        final enrollment = _asMap(started['enrollment']);
        final pairingPayload = _asMap(started['qr_payload']);
        return LocalSyncBootstrapResult(
          status: 'enrollment_pending',
          message:
              'Approve this register from an existing trusted Neuradix POS device.',
          enrollmentId: '${enrollment['name'] ?? ''}',
          pairingPayload: Map<String, Object?>.from(pairingPayload),
        );
      }
      return const LocalSyncBootstrapResult(
        status: 'enrollment_required',
        message:
            'Approve this device from an existing trusted Neuradix POS device.',
      );
    }

    final keyEpoch = int.tryParse('${currentDevice['key_epoch'] ?? 1}') ?? 1;
    keys ??= await keyManager.load(
      businessId: businessId,
      deviceId: deviceId,
      keyEpoch: keyEpoch,
    );
    if (keys == null) {
      return const LocalSyncBootstrapResult(
        status: 'key_recovery_required',
        message:
            'This installation no longer holds its device keys. Re-enroll it from a trusted device.',
      );
    }

    final shops = _mapList(metadata['shops']);
    final fallbackShop = _asMap(metadata['shop']);
    final shopId = '${currentDevice['shop'] ?? fallbackShop['name'] ?? ''}';
    final shop = shops.cast<Map<String, dynamic>?>().firstWhere(
      (Map<String, dynamic>? row) => '${row?['name'] ?? ''}' == shopId,
      orElse: () => fallbackShop,
    );
    final profile = LocalSyncProfile(
      businessId: businessId,
      shopId: shopId,
      shopName:
          '${currentDevice['shop_name'] ?? shop?['shop_name'] ?? fallbackShop['shop_name'] ?? ''}',
      deviceId: deviceId,
      deviceName: '${currentDevice['device_name'] ?? deviceName}',
      relayUrl: '${metadata['relay_url'] ?? fallbackRelayUrl}',
      protocolVersion:
          int.tryParse('${metadata['protocol_version']}') ??
          fallbackProtocolVersion,
      keyEpoch: keyEpoch,
      isPreferredPeer:
          currentDevice['is_preferred_peer'] == true ||
          currentDevice['is_preferred_peer'] == 1 ||
          currentDevice['is_preferred_peer'] == '1',
    );
    await repository.saveProfile(profile);
    for (final peer in devices) {
      final peerDeviceId = '${peer['device_id'] ?? ''}';
      if (peerDeviceId.isEmpty || peerDeviceId == deviceId) {
        continue;
      }
      await repository.upsertPeer(
        deviceId: peerDeviceId,
        shopId: '${peer['shop'] ?? ''}',
        deviceName: '${peer['device_name'] ?? peerDeviceId}',
        signingPublicKey: '${peer['signing_public_key'] ?? ''}',
        exchangePublicKey: '${peer['exchange_public_key'] ?? ''}',
        status: '${peer['status'] ?? 'revoked'}',
        keyEpoch: int.tryParse('${peer['key_epoch'] ?? 1}') ?? 1,
      );
    }
    final coordinator = _coordinator(profile, keys);
    return LocalSyncBootstrapResult(
      status: 'ready',
      message: 'Local multi-shop changes are queued for trusted devices.',
      coordinator: coordinator,
      profile: profile,
    );
  }

  Future<LocalSyncCoordinator?> _restoreCoordinator({
    required String businessId,
    required String deviceId,
  }) async {
    final profile = await repository.readProfile();
    if (profile == null ||
        profile.businessId != businessId ||
        profile.deviceId != deviceId) {
      return null;
    }
    final keys = await keyManager.load(
      businessId: businessId,
      deviceId: deviceId,
      keyEpoch: profile.keyEpoch,
    );
    return keys == null ? null : _coordinator(profile, keys);
  }

  LocalSyncCoordinator _coordinator(
    LocalSyncProfile profile,
    LocalSyncDeviceKeys keys,
  ) {
    return LocalSyncCoordinator(
      profile: profile,
      keys: keys,
      repository: repository,
      clock: HybridLogicalClock(nodeId: profile.deviceId),
    );
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    return ((value as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((Map row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Map<String, dynamic> _asMap(Object? value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  Map<String, dynamic>? _findDevice(
    List<Map<String, dynamic>> devices,
    String deviceId,
  ) {
    for (final device in devices) {
      if ('${device['device_id'] ?? ''}' == deviceId) {
        return device;
      }
    }
    return null;
  }
}
