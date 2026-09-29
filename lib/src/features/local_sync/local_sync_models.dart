import 'dart:convert';

enum LocalSyncEntityType {
  inventoryItem('inventory_item'),
  customer('customer'),
  finalizedSale('finalized_sale');

  const LocalSyncEntityType(this.value);

  final String value;

  static LocalSyncEntityType parse(String value) {
    return LocalSyncEntityType.values.firstWhere(
      (LocalSyncEntityType type) => type.value == value,
      orElse:
          () => throw FormatException('Unsupported sync entity type: $value'),
    );
  }
}

enum LocalSyncOperation {
  upsert('upsert'),
  finalize('finalize');

  const LocalSyncOperation(this.value);

  final String value;

  static LocalSyncOperation parse(String value) {
    return LocalSyncOperation.values.firstWhere(
      (LocalSyncOperation operation) => operation.value == value,
      orElse: () => throw FormatException('Unsupported sync operation: $value'),
    );
  }
}

class LocalSyncProfile {
  const LocalSyncProfile({
    required this.businessId,
    required this.shopId,
    required this.shopName,
    required this.deviceId,
    required this.deviceName,
    required this.relayUrl,
    required this.protocolVersion,
    required this.keyEpoch,
    this.isPreferredPeer = false,
  });

  final String businessId;
  final String shopId;
  final String shopName;
  final String deviceId;
  final String deviceName;
  final String relayUrl;
  final int protocolVersion;
  final int keyEpoch;
  final bool isPreferredPeer;

  factory LocalSyncProfile.fromRow(Map<String, Object?> row) {
    return LocalSyncProfile(
      businessId: '${row['business_id']}',
      shopId: '${row['shop_id']}',
      shopName: '${row['shop_name']}',
      deviceId: '${row['device_id']}',
      deviceName: '${row['device_name']}',
      relayUrl: '${row['relay_url']}',
      protocolVersion: int.tryParse('${row['protocol_version']}') ?? 1,
      keyEpoch: int.tryParse('${row['key_epoch']}') ?? 1,
      isPreferredPeer: row['is_preferred_peer'] == 1,
    );
  }

  Map<String, Object?> toRow({required String updatedAt}) {
    return <String, Object?>{
      'profile_id': 1,
      'business_id': businessId,
      'shop_id': shopId,
      'shop_name': shopName,
      'device_id': deviceId,
      'device_name': deviceName,
      'relay_url': relayUrl,
      'protocol_version': protocolVersion,
      'key_epoch': keyEpoch,
      'is_preferred_peer': isPreferredPeer ? 1 : 0,
      'updated_at': updatedAt,
    };
  }
}

class LocalSyncShop {
  const LocalSyncShop({
    required this.shopId,
    required this.shopName,
    required this.shopCode,
    required this.status,
    required this.isDefault,
  });

  final String shopId;
  final String shopName;
  final String shopCode;
  final String status;
  final bool isDefault;

  bool get isActive => status == 'active';

  factory LocalSyncShop.fromJson(Map<String, dynamic> json) {
    return LocalSyncShop(
      shopId: '${json['name'] ?? json['shop_id'] ?? ''}',
      shopName: '${json['shop_name'] ?? ''}',
      shopCode: '${json['shop_code'] ?? ''}',
      status: '${json['status'] ?? 'active'}',
      isDefault: _localSyncBool(json['is_default']),
    );
  }
}

class LocalSyncDeviceSummary {
  const LocalSyncDeviceSummary({
    required this.deviceId,
    required this.deviceName,
    required this.shopId,
    required this.shopName,
    required this.status,
    required this.isPreferredPeer,
    required this.lastSeenOn,
  });

  final String deviceId;
  final String deviceName;
  final String shopId;
  final String shopName;
  final String status;
  final bool isPreferredPeer;
  final String lastSeenOn;

  bool get isActive => status == 'active';

  factory LocalSyncDeviceSummary.fromJson(Map<String, dynamic> json) {
    return LocalSyncDeviceSummary(
      deviceId: '${json['device_id'] ?? ''}',
      deviceName: '${json['device_name'] ?? ''}',
      shopId: '${json['shop'] ?? json['shop_id'] ?? ''}',
      shopName: '${json['shop_name'] ?? ''}',
      status: '${json['status'] ?? ''}',
      isPreferredPeer: _localSyncBool(json['is_preferred_peer']),
      lastSeenOn: '${json['last_seen_on'] ?? ''}',
    );
  }
}

class LocalSyncMetadata {
  const LocalSyncMetadata({
    required this.businessId,
    required this.businessName,
    required this.relayUrl,
    required this.protocolVersion,
    required this.maxDevices,
    required this.shops,
    required this.devices,
  });

  final String businessId;
  final String businessName;
  final String relayUrl;
  final int protocolVersion;
  final int maxDevices;
  final List<LocalSyncShop> shops;
  final List<LocalSyncDeviceSummary> devices;

  List<LocalSyncShop> get activeShops => shops
      .where((LocalSyncShop shop) => shop.isActive)
      .toList(growable: false);

  LocalSyncDeviceSummary? device(String deviceId) {
    for (final device in devices) {
      if (device.deviceId == deviceId) {
        return device;
      }
    }
    return null;
  }

  bool requiresShopSelectionFor(String deviceId) {
    final current = device(deviceId);
    return (current == null || !current.isActive) &&
        devices.any((LocalSyncDeviceSummary device) => device.isActive);
  }

  factory LocalSyncMetadata.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? value) {
      return ((value as List?) ?? const <Object?>[])
          .whereType<Map>()
          .map((Map row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

    return LocalSyncMetadata(
      businessId: '${json['business_id'] ?? ''}',
      businessName: '${json['business_name'] ?? ''}',
      relayUrl: '${json['relay_url'] ?? ''}',
      protocolVersion: int.tryParse('${json['protocol_version'] ?? 1}') ?? 1,
      maxDevices: int.tryParse('${json['max_devices'] ?? 0}') ?? 0,
      shops: maps(
        json['shops'],
      ).map(LocalSyncShop.fromJson).toList(growable: false),
      devices: maps(
        json['devices'],
      ).map(LocalSyncDeviceSummary.fromJson).toList(growable: false),
    );
  }
}

bool _localSyncBool(Object? value) =>
    value == true || value == 1 || value == '1';

class LocalSyncEnvelope {
  const LocalSyncEnvelope({
    required this.protocolVersion,
    required this.eventId,
    required this.businessId,
    required this.shopId,
    required this.originDeviceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.hlc,
    required this.keyEpoch,
    required this.createdAt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.signature,
  });

  final int protocolVersion;
  final String eventId;
  final String businessId;
  final String shopId;
  final String originDeviceId;
  final LocalSyncEntityType entityType;
  final String entityId;
  final LocalSyncOperation operation;
  final String hlc;
  final int keyEpoch;
  final String createdAt;
  final String nonce;
  final String ciphertext;
  final String mac;
  final String signature;

  Map<String, Object?> get header => <String, Object?>{
    'protocol_version': protocolVersion,
    'event_id': eventId,
    'business_id': businessId,
    'shop_id': shopId,
    'origin_device_id': originDeviceId,
    'entity_type': entityType.value,
    'entity_id': entityId,
    'operation': operation.value,
    'hlc': hlc,
    'key_epoch': keyEpoch,
    'created_at': createdAt,
  };

  Map<String, Object?> get signedBody => <String, Object?>{
    ...header,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ...signedBody,
    'signature': signature,
  };

  String encode() => jsonEncode(toJson());

  factory LocalSyncEnvelope.decode(String value) {
    return LocalSyncEnvelope.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map),
    );
  }

  factory LocalSyncEnvelope.fromJson(Map<String, dynamic> json) {
    return LocalSyncEnvelope(
      protocolVersion: int.tryParse('${json['protocol_version']}') ?? 1,
      eventId: '${json['event_id'] ?? ''}',
      businessId: '${json['business_id'] ?? ''}',
      shopId: '${json['shop_id'] ?? ''}',
      originDeviceId: '${json['origin_device_id'] ?? ''}',
      entityType: LocalSyncEntityType.parse('${json['entity_type'] ?? ''}'),
      entityId: '${json['entity_id'] ?? ''}',
      operation: LocalSyncOperation.parse('${json['operation'] ?? ''}'),
      hlc: '${json['hlc'] ?? ''}',
      keyEpoch: int.tryParse('${json['key_epoch']}') ?? 1,
      createdAt: '${json['created_at'] ?? ''}',
      nonce: '${json['nonce'] ?? ''}',
      ciphertext: '${json['ciphertext'] ?? ''}',
      mac: '${json['mac'] ?? ''}',
      signature: '${json['signature'] ?? ''}',
    );
  }
}

class LocalSyncPendingEvent {
  const LocalSyncPendingEvent({
    required this.envelope,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    this.lastError = '',
  });

  final LocalSyncEnvelope envelope;
  final String status;
  final int attemptCount;
  final String createdAt;
  final String lastError;
}

class LocalSyncApplyResult {
  const LocalSyncApplyResult({
    required this.eventId,
    required this.status,
    required this.materialized,
  });

  final String eventId;
  final String status;
  final bool materialized;

  bool get isDuplicate => status == 'duplicate';
  bool get isConflict => status == 'conflict';
}

String canonicalJsonEncode(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((Object? key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in sortedKeys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return value.map<Object?>(_canonicalize).toList(growable: false);
  }
  return value;
}
