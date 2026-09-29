import 'dart:convert';

import '../../data/local/local_sync_repository.dart';
import '../hosted/hosted_models.dart';
import 'hybrid_logical_clock.dart';
import 'local_sync_crypto.dart';
import 'local_sync_ids.dart';
import 'local_sync_models.dart';

class LocalSyncCoordinator {
  LocalSyncCoordinator({
    required this.profile,
    required this.keys,
    required this.repository,
    required this.clock,
    LocalSyncCrypto? crypto,
    String Function()? eventIdGenerator,
  }) : _crypto = crypto ?? LocalSyncCrypto(),
       _eventIdGenerator = eventIdGenerator ?? generateLocalSyncId;

  final LocalSyncProfile profile;
  final LocalSyncDeviceKeys keys;
  final LocalSyncRepository repository;
  final HybridLogicalClock clock;
  final LocalSyncCrypto _crypto;
  final String Function() _eventIdGenerator;

  Future<LocalSyncEnvelope> saveInventoryItem(HostedInventoryItem item) async {
    final envelope = await _createEnvelope(
      entityType: LocalSyncEntityType.inventoryItem,
      entityId: item.itemId,
      operation: LocalSyncOperation.upsert,
      payload: <String, Object?>{
        'schema_version': 1,
        'inventory_item': item.toApiPayload(),
      },
    );
    await repository.commitInventoryItemAndEvent(
      item: item,
      envelope: envelope,
    );
    return envelope;
  }

  Future<LocalSyncEnvelope> saveCustomer(HostedCustomer customer) async {
    final envelope = await _createEnvelope(
      entityType: LocalSyncEntityType.customer,
      entityId: customer.customerId,
      operation: LocalSyncOperation.upsert,
      payload: <String, Object?>{
        'schema_version': 1,
        'customer': customer.toJson(),
      },
    );
    await repository.commitCustomerAndEvent(
      customer: customer,
      envelope: envelope,
    );
    return envelope;
  }

  Future<LocalSyncEnvelope> saveFinalizedSale(HostedSaleRecord sale) async {
    if (sale.status == 'parked' || sale.status == 'draft') {
      throw ArgumentError('Draft and parked sales must not be replicated.');
    }
    final envelope = await _createEnvelope(
      entityType: LocalSyncEntityType.finalizedSale,
      entityId: sale.saleId,
      operation: LocalSyncOperation.finalize,
      payload: <String, Object?>{'schema_version': 1, 'sale': sale.toJson()},
    );
    await repository.commitFinalizedSaleAndEvent(
      sale: sale,
      envelope: envelope,
    );
    return envelope;
  }

  Future<LocalSyncApplyResult> applyEnvelope(LocalSyncEnvelope envelope) async {
    if (envelope.protocolVersion != profile.protocolVersion) {
      throw StateError('Unsupported local sync protocol version.');
    }
    if (envelope.businessId != profile.businessId) {
      throw StateError('Cross-business sync events are not accepted.');
    }
    if (envelope.keyEpoch != keys.keyEpoch) {
      throw StateError('The sync event uses an unavailable key epoch.');
    }
    final peer = await repository.readPeer(envelope.originDeviceId);
    if (peer == null || '${peer['status']}' != 'active') {
      throw StateError('The event origin is not an active trusted device.');
    }
    if ((int.tryParse('${peer['key_epoch']}') ?? 0) != envelope.keyEpoch) {
      throw StateError(
        'The trusted device key epoch does not match the event.',
      );
    }

    final payload = await _crypto.verifyAndDecrypt(
      envelope: envelope,
      signingPublicKey: base64Decode('${peer['signing_public_key']}'),
      businessKey: keys.businessKey,
    );
    final result = await repository.applyIncoming(
      envelope: envelope,
      payload: payload,
    );
    clock.observe(HybridLogicalTimestamp.parse(envelope.hlc));
    await repository.updatePeerCursor(
      deviceId: envelope.originDeviceId,
      hlc: envelope.hlc,
    );
    return result;
  }

  Future<void> refreshTrustedPeers(Map<String, dynamic> metadata) async {
    final devices = ((metadata['devices'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((Map row) => Map<String, dynamic>.from(row));
    for (final peer in devices) {
      final peerDeviceId = '${peer['device_id'] ?? ''}';
      if (peerDeviceId.isEmpty || peerDeviceId == profile.deviceId) {
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
  }

  Future<LocalSyncEnvelope> _createEnvelope({
    required LocalSyncEntityType entityType,
    required String entityId,
    required LocalSyncOperation operation,
    required Map<String, Object?> payload,
  }) {
    if (entityId.trim().isEmpty) {
      throw ArgumentError.value(entityId, 'entityId', 'must not be empty');
    }
    return _crypto.encryptAndSign(
      profile: profile,
      keys: keys,
      eventId: _eventIdGenerator(),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      hlc: clock.tick().toString(),
      payload: payload,
    );
  }
}
