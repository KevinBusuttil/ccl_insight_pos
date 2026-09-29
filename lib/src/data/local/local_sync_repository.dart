import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/hosted/hosted_models.dart';
import '../../features/local_sync/hybrid_logical_clock.dart';
import '../../features/local_sync/local_sync_models.dart';

class LocalSyncRepository {
  LocalSyncRepository(this.database);

  static const List<String> _customerFields = <String>[
    'customer_code',
    'customer_name',
    'mobile_no',
    'email_id',
    'primary_address',
    'is_active',
  ];

  final Database database;

  Future<void> saveProfile(LocalSyncProfile profile) async {
    final row = profile.toRow(updatedAt: _now());
    await database.rawInsert(
      '''
      INSERT INTO local_sync_profile (
        profile_id, business_id, shop_id, shop_name, device_id, device_name,
        relay_url, protocol_version, key_epoch, is_preferred_peer, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(profile_id) DO UPDATE SET
        business_id = excluded.business_id,
        shop_id = excluded.shop_id,
        shop_name = excluded.shop_name,
        device_id = excluded.device_id,
        device_name = excluded.device_name,
        relay_url = excluded.relay_url,
        protocol_version = excluded.protocol_version,
        key_epoch = excluded.key_epoch,
        is_preferred_peer = excluded.is_preferred_peer,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        row['profile_id'],
        row['business_id'],
        row['shop_id'],
        row['shop_name'],
        row['device_id'],
        row['device_name'],
        row['relay_url'],
        row['protocol_version'],
        row['key_epoch'],
        row['is_preferred_peer'],
        row['updated_at'],
      ],
    );
  }

  Future<LocalSyncProfile?> readProfile() async {
    final rows = await database.rawQuery(
      'SELECT * FROM local_sync_profile WHERE profile_id = 1 LIMIT 1',
    );
    return rows.isEmpty ? null : LocalSyncProfile.fromRow(rows.single);
  }

  Future<void> upsertPeer({
    required String deviceId,
    required String shopId,
    required String deviceName,
    required String signingPublicKey,
    required String exchangePublicKey,
    required String status,
    required int keyEpoch,
    String lastHlc = '',
  }) async {
    await database.rawInsert(
      '''
      INSERT INTO local_sync_peers (
        device_id, shop_id, device_name, signing_public_key,
        exchange_public_key, status, key_epoch, last_seen_at, last_hlc
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        shop_id = excluded.shop_id,
        device_name = excluded.device_name,
        signing_public_key = excluded.signing_public_key,
        exchange_public_key = excluded.exchange_public_key,
        status = excluded.status,
        key_epoch = excluded.key_epoch,
        last_seen_at = excluded.last_seen_at,
        last_hlc = CASE
          WHEN excluded.last_hlc = '' THEN local_sync_peers.last_hlc
          ELSE excluded.last_hlc
        END
      ''',
      <Object?>[
        deviceId,
        shopId,
        deviceName,
        signingPublicKey,
        exchangePublicKey,
        status,
        keyEpoch,
        _now(),
        lastHlc,
      ],
    );
    if (status == 'active') {
      await database.rawUpdate(
        '''
        UPDATE local_sync_events
        SET status = 'pending', updated_at = ?
        WHERE direction = 'outgoing'
          AND status = 'acknowledged'
          AND origin_device_id != ?
          AND (entity_type != 'inventory_item' OR shop_id = ?)
          AND NOT EXISTS (
            SELECT 1
            FROM local_sync_event_receipts receipt
            WHERE receipt.event_id = local_sync_events.event_id
              AND receipt.peer_device_id = ?
          )
        ''',
        <Object?>[_now(), deviceId, shopId, deviceId],
      );
    }
  }

  Future<Map<String, Object?>?> readPeer(String deviceId) async {
    final rows = await database.rawQuery(
      'SELECT * FROM local_sync_peers WHERE device_id = ? LIMIT 1',
      <Object?>[deviceId],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> updatePeerCursor({
    required String deviceId,
    required String hlc,
  }) async {
    await database.rawUpdate(
      '''
      UPDATE local_sync_peers
      SET last_hlc = ?, last_seen_at = ?
      WHERE device_id = ? AND status = 'active'
      ''',
      <Object?>[hlc, _now(), deviceId],
    );
  }

  Future<void> commitCustomerAndEvent({
    required HostedCustomer customer,
    required LocalSyncEnvelope envelope,
  }) async {
    _validateEnvelope(
      envelope,
      expectedType: LocalSyncEntityType.customer,
      expectedEntityId: customer.customerId,
    );
    await database.transaction((Transaction transaction) async {
      await _upsertCustomer(transaction, customer);
      await _insertOutgoingEvent(transaction, envelope);
      await _writeCustomerFieldVersions(
        transaction,
        entityId: customer.customerId,
        hlc: envelope.hlc,
        originDeviceId: envelope.originDeviceId,
      );
      await _writeEntityVersion(transaction, envelope);
    });
  }

  Future<void> commitInventoryItemAndEvent({
    required HostedInventoryItem item,
    required LocalSyncEnvelope envelope,
  }) async {
    _validateEnvelope(
      envelope,
      expectedType: LocalSyncEntityType.inventoryItem,
      expectedEntityId: item.itemId,
    );
    await database.transaction((Transaction transaction) async {
      await _upsertInventoryItem(transaction, item);
      await _insertOutgoingEvent(transaction, envelope);
      await _writeEntityVersion(transaction, envelope);
    });
  }

  Future<void> commitFinalizedSaleAndEvent({
    required HostedSaleRecord sale,
    required LocalSyncEnvelope envelope,
  }) async {
    _validateEnvelope(
      envelope,
      expectedType: LocalSyncEntityType.finalizedSale,
      expectedEntityId: sale.saleId,
    );
    await database.transaction((Transaction transaction) async {
      await _saveSale(transaction, sale);
      await _insertOutgoingEvent(transaction, envelope);
      await _writeEntityVersion(transaction, envelope);
    });
  }

  Future<List<LocalSyncPendingEvent>> readPendingEvents({
    int limit = 100,
  }) async {
    final rows = await database.rawQuery(
      '''
      SELECT envelope_json, status, attempt_count, last_error, created_at
      FROM local_sync_events
      WHERE direction = 'outgoing'
        AND status IN ('pending', 'retry', 'sent')
      ORDER BY hlc ASC, event_id ASC
      LIMIT ?
      ''',
      <Object?>[limit],
    );
    return rows
        .map(
          (Map<String, Object?> row) => LocalSyncPendingEvent(
            envelope: LocalSyncEnvelope.decode('${row['envelope_json']}'),
            status: '${row['status']}',
            attemptCount: int.tryParse('${row['attempt_count']}') ?? 0,
            lastError: '${row['last_error'] ?? ''}',
            createdAt: '${row['created_at']}',
          ),
        )
        .toList(growable: false);
  }

  Future<void> markSent(String eventId) async {
    await database.rawUpdate(
      '''
      UPDATE local_sync_events
      SET status = CASE
            WHEN NOT EXISTS (
              SELECT 1
              FROM local_sync_peers peer
              WHERE peer.status = 'active'
                AND peer.device_id != local_sync_events.origin_device_id
                AND (
                  local_sync_events.entity_type != 'inventory_item'
                  OR peer.shop_id = local_sync_events.shop_id
                )
            ) THEN 'acknowledged'
            ELSE 'sent'
          END,
          attempt_count = attempt_count + 1,
          last_error = '',
          updated_at = ?
      WHERE event_id = ? AND direction = 'outgoing'
      ''',
      <Object?>[_now(), eventId],
    );
  }

  Future<void> markRetry(String eventId, Object error) async {
    await database.rawUpdate(
      '''
      UPDATE local_sync_events
      SET status = 'retry',
          attempt_count = attempt_count + 1,
          last_error = ?,
          updated_at = ?
      WHERE event_id = ? AND direction = 'outgoing'
      ''',
      <Object?>['$error', _now(), eventId],
    );
  }

  Future<void> acknowledge({
    required String eventId,
    required String peerDeviceId,
  }) async {
    final acknowledgedAt = _now();
    await database.transaction((Transaction transaction) async {
      await transaction.rawInsert(
        '''
        INSERT INTO local_sync_event_receipts (
          event_id, peer_device_id, acknowledged_at
        ) VALUES (?, ?, ?)
        ON CONFLICT(event_id, peer_device_id) DO UPDATE SET
          acknowledged_at = excluded.acknowledged_at
        ''',
        <Object?>[eventId, peerDeviceId, acknowledgedAt],
      );
      await transaction.rawUpdate(
        '''
        UPDATE local_sync_events
        SET status = 'acknowledged', updated_at = ?
        WHERE event_id = ?
          AND direction = 'outgoing'
          AND NOT EXISTS (
            SELECT 1
            FROM local_sync_peers peer
            WHERE peer.status = 'active'
              AND peer.device_id != local_sync_events.origin_device_id
              AND (
                local_sync_events.entity_type != 'inventory_item'
                OR peer.shop_id = local_sync_events.shop_id
              )
              AND NOT EXISTS (
                SELECT 1
                FROM local_sync_event_receipts receipt
                WHERE receipt.event_id = local_sync_events.event_id
                  AND receipt.peer_device_id = peer.device_id
              )
          )
        ''',
        <Object?>[acknowledgedAt, eventId],
      );
    });
  }

  Future<LocalSyncApplyResult> applyIncoming({
    required LocalSyncEnvelope envelope,
    required Map<String, dynamic> payload,
  }) async {
    final profile = await readProfile();
    if (profile == null || profile.businessId != envelope.businessId) {
      throw StateError('The sync event does not belong to this business.');
    }

    return database.transaction((Transaction transaction) async {
      final existingEvent = await transaction.rawQuery(
        'SELECT status FROM local_sync_events WHERE event_id = ? LIMIT 1',
        <Object?>[envelope.eventId],
      );
      if (existingEvent.isNotEmpty) {
        return LocalSyncApplyResult(
          eventId: envelope.eventId,
          status: 'duplicate',
          materialized: false,
        );
      }

      switch (envelope.entityType) {
        case LocalSyncEntityType.inventoryItem:
          if (envelope.shopId != profile.shopId) {
            await _insertIncomingEvent(
              transaction,
              envelope,
              status: 'ignored_shop_scope',
            );
            return LocalSyncApplyResult(
              eventId: envelope.eventId,
              status: 'ignored_shop_scope',
              materialized: false,
            );
          }
          return _applyIncomingInventoryItem(transaction, envelope, payload);
        case LocalSyncEntityType.customer:
          return _applyIncomingCustomer(transaction, envelope, payload);
        case LocalSyncEntityType.finalizedSale:
          return _applyIncomingSale(transaction, envelope, payload);
      }
    });
  }

  Future<int> pendingEventCount() async {
    final rows = await database.rawQuery('''
      SELECT COUNT(*)
      FROM local_sync_events
      WHERE direction = 'outgoing'
        AND status IN ('pending', 'retry', 'sent')
      ''');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<String?> lastSuccessfulSyncAt() async {
    final rows = await database.rawQuery('''
      SELECT MAX(updated_at) AS last_synced_at
      FROM local_sync_events
      WHERE status IN ('acknowledged', 'applied', 'duplicate')
      ''');
    final value = rows.isEmpty ? null : rows.single['last_synced_at'];
    final normalized = '${value ?? ''}'.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<int> conflictCount() async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) FROM local_sync_conflicts WHERE resolved_at IS NULL',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<LocalSyncApplyResult> _applyIncomingCustomer(
    Transaction transaction,
    LocalSyncEnvelope envelope,
    Map<String, dynamic> payload,
  ) async {
    final rawCustomer = payload['customer'];
    if (rawCustomer is! Map) {
      throw const FormatException(
        'Customer sync event has no customer object.',
      );
    }
    final incoming = Map<String, dynamic>.from(rawCustomer);
    incoming['name'] = envelope.entityId;
    final existingRows = await transaction.rawQuery(
      'SELECT payload_json FROM hosted_customers WHERE customer_id = ? LIMIT 1',
      <Object?>[envelope.entityId],
    );
    final merged =
        existingRows.isEmpty
            ? <String, dynamic>{'name': envelope.entityId}
            : Map<String, dynamic>.from(
              jsonDecode('${existingRows.single['payload_json']}') as Map,
            );
    final versionRows = await transaction.rawQuery(
      '''
      SELECT field_name, hlc
      FROM local_sync_field_versions
      WHERE entity_type = ? AND entity_id = ?
      ''',
      <Object?>[LocalSyncEntityType.customer.value, envelope.entityId],
    );
    final localVersions = <String, HybridLogicalTimestamp>{
      for (final row in versionRows)
        '${row['field_name']}': HybridLogicalTimestamp.parse('${row['hlc']}'),
    };
    final incomingVersion = HybridLogicalTimestamp.parse(envelope.hlc);
    final changedFields = <String>[];
    for (final field in _customerFields) {
      final localVersion = localVersions[field];
      if (localVersion == null || incomingVersion.compareTo(localVersion) > 0) {
        merged[field] = incoming[field];
        changedFields.add(field);
      }
    }
    merged['name'] = envelope.entityId;
    merged['updated_at'] = envelope.createdAt;

    var status = changedFields.isEmpty ? 'ignored' : 'applied';
    if (changedFields.isNotEmpty) {
      final customer = HostedCustomer.fromApi(merged);
      await _upsertCustomer(transaction, customer);
      for (final field in changedFields) {
        await _writeFieldVersion(
          transaction,
          entityType: envelope.entityType.value,
          entityId: envelope.entityId,
          fieldName: field,
          hlc: envelope.hlc,
          originDeviceId: envelope.originDeviceId,
        );
      }
      if (customer.mobileNo.trim().isNotEmpty &&
          await _hasCustomerWithSameMobile(
            transaction,
            customerId: customer.customerId,
            mobileNo: customer.mobileNo,
          )) {
        status = 'applied_with_conflict';
        await _insertConflict(
          transaction,
          envelope: envelope,
          localHlc: localVersions['mobile_no']?.toString() ?? '',
          reason: 'possible_duplicate_mobile',
          details: <String, Object?>{'mobile_no': customer.mobileNo},
        );
      }
      await _writeEntityVersion(transaction, envelope);
    }
    await _insertIncomingEvent(transaction, envelope, status: status);
    return LocalSyncApplyResult(
      eventId: envelope.eventId,
      status: status,
      materialized: changedFields.isNotEmpty,
    );
  }

  Future<LocalSyncApplyResult> _applyIncomingInventoryItem(
    Transaction transaction,
    LocalSyncEnvelope envelope,
    Map<String, dynamic> payload,
  ) async {
    final rawItem = payload['inventory_item'];
    if (rawItem is! Map) {
      throw const FormatException(
        'Inventory sync event has no inventory item object.',
      );
    }
    final itemJson = Map<String, dynamic>.from(rawItem);
    itemJson['item_id'] = envelope.entityId;
    final item = HostedInventoryItem.fromApi(itemJson);
    await _upsertInventoryItem(transaction, item);
    await _writeEntityVersion(transaction, envelope);
    await _insertIncomingEvent(transaction, envelope, status: 'applied');
    return LocalSyncApplyResult(
      eventId: envelope.eventId,
      status: 'applied',
      materialized: true,
    );
  }

  Future<void> _upsertInventoryItem(
    DatabaseExecutor executor,
    HostedInventoryItem item,
  ) async {
    final row = item.toRow();
    await executor.rawInsert(
      '''
      INSERT INTO hosted_inventory_items (
        item_id, sku, barcode, display_name, image_url, price, stock_qty,
        is_active, payload_json, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(item_id) DO UPDATE SET
        sku = excluded.sku,
        barcode = excluded.barcode,
        display_name = excluded.display_name,
        image_url = excluded.image_url,
        price = excluded.price,
        stock_qty = excluded.stock_qty,
        is_active = excluded.is_active,
        payload_json = excluded.payload_json,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        row['item_id'],
        row['sku'],
        row['barcode'],
        row['display_name'],
        row['image_url'],
        row['price'],
        row['stock_qty'],
        row['is_active'],
        row['payload_json'],
        row['updated_at'],
      ],
    );
  }

  Future<LocalSyncApplyResult> _applyIncomingSale(
    Transaction transaction,
    LocalSyncEnvelope envelope,
    Map<String, dynamic> payload,
  ) async {
    final rawSale = payload['sale'];
    if (rawSale is! Map) {
      throw const FormatException('Sale sync event has no sale object.');
    }
    final incomingJson = Map<String, dynamic>.from(rawSale);
    incomingJson['sale_id'] = envelope.entityId;
    final incoming = HostedSaleRecord.fromJson(incomingJson);
    final existingRows = await transaction.rawQuery(
      'SELECT payload_json FROM hosted_sales WHERE sale_id = ? LIMIT 1',
      <Object?>[envelope.entityId],
    );
    if (existingRows.isNotEmpty) {
      final existing = HostedSaleRecord.fromJson(
        Map<String, dynamic>.from(
          jsonDecode('${existingRows.single['payload_json']}') as Map,
        ),
      );
      if (_saleFingerprint(existing) != _saleFingerprint(incoming)) {
        await _insertConflict(
          transaction,
          envelope: envelope,
          localHlc: await _readEntityHlc(
            transaction,
            envelope.entityType.value,
            envelope.entityId,
          ),
          reason: 'immutable_sale_mismatch',
          details: <String, Object?>{
            'existing': existing.toJson(),
            'incoming': incoming.toJson(),
          },
        );
        await _insertIncomingEvent(transaction, envelope, status: 'conflict');
        return LocalSyncApplyResult(
          eventId: envelope.eventId,
          status: 'conflict',
          materialized: false,
        );
      }
      await _insertIncomingEvent(transaction, envelope, status: 'ignored');
      return LocalSyncApplyResult(
        eventId: envelope.eventId,
        status: 'ignored',
        materialized: false,
      );
    }

    final materialized = HostedSaleRecord(
      saleId: incoming.saleId,
      remoteSaleId: incoming.remoteSaleId,
      customerId: incoming.customerId,
      customerName: incoming.customerName,
      postingDate: incoming.postingDate,
      totalAmount: incoming.totalAmount,
      status: 'replicated',
      items: incoming.items,
      updatedAt: envelope.createdAt,
    );
    await _saveSale(transaction, materialized);
    await _writeEntityVersion(transaction, envelope);
    await _insertIncomingEvent(transaction, envelope, status: 'applied');
    return LocalSyncApplyResult(
      eventId: envelope.eventId,
      status: 'applied',
      materialized: true,
    );
  }

  Future<void> _upsertCustomer(
    DatabaseExecutor executor,
    HostedCustomer customer,
  ) async {
    final row = customer.toRow();
    await executor.rawInsert(
      '''
      INSERT INTO hosted_customers (
        customer_id, customer_code, display_name, mobile_no, email_id,
        primary_address, is_active, payload_json, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(customer_id) DO UPDATE SET
        customer_code = excluded.customer_code,
        display_name = excluded.display_name,
        mobile_no = excluded.mobile_no,
        email_id = excluded.email_id,
        primary_address = excluded.primary_address,
        is_active = excluded.is_active,
        payload_json = excluded.payload_json,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        row['customer_id'],
        row['customer_code'],
        row['display_name'],
        row['mobile_no'],
        row['email_id'],
        row['primary_address'],
        row['is_active'],
        row['payload_json'],
        row['updated_at'],
      ],
    );
  }

  Future<void> _saveSale(
    DatabaseExecutor executor,
    HostedSaleRecord sale,
  ) async {
    final row = sale.toSaleRow();
    await executor.rawInsert(
      '''
      INSERT INTO hosted_sales (
        sale_id, remote_sale_id, customer_id, customer_name, posting_date,
        total_amount, status, payload_json, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(sale_id) DO UPDATE SET
        remote_sale_id = excluded.remote_sale_id,
        customer_id = excluded.customer_id,
        customer_name = excluded.customer_name,
        posting_date = excluded.posting_date,
        total_amount = excluded.total_amount,
        status = excluded.status,
        payload_json = excluded.payload_json,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        row['sale_id'],
        row['remote_sale_id'],
        row['customer_id'],
        row['customer_name'],
        row['posting_date'],
        row['total_amount'],
        row['status'],
        row['payload_json'],
        row['updated_at'],
      ],
    );
    await executor.rawDelete(
      'DELETE FROM hosted_sale_items WHERE sale_id = ?',
      <Object?>[sale.saleId],
    );
    for (final item in sale.items) {
      await executor.rawInsert(
        '''
        INSERT INTO hosted_sale_items (
          sale_id, item_id, sku, barcode, display_name, qty, rate,
          discount_amount, tax_amount, amount, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          sale.saleId,
          item.itemId,
          item.sku,
          item.barcode,
          item.displayName,
          item.qty,
          item.rate,
          item.discountAmount,
          item.taxAmount,
          item.amount,
          item.notes,
        ],
      );
    }
  }

  Future<void> _insertOutgoingEvent(
    Transaction transaction,
    LocalSyncEnvelope envelope,
  ) {
    return _insertEvent(
      transaction,
      envelope,
      direction: 'outgoing',
      status: 'pending',
    );
  }

  Future<void> _insertIncomingEvent(
    Transaction transaction,
    LocalSyncEnvelope envelope, {
    required String status,
  }) {
    return _insertEvent(
      transaction,
      envelope,
      direction: 'incoming',
      status: status,
    );
  }

  Future<void> _insertEvent(
    Transaction transaction,
    LocalSyncEnvelope envelope, {
    required String direction,
    required String status,
  }) async {
    final now = _now();
    await transaction.rawInsert(
      '''
      INSERT INTO local_sync_events (
        event_id, direction, business_id, shop_id, origin_device_id,
        entity_type, entity_id, operation, hlc, envelope_json, status,
        attempt_count, last_error, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, '', ?, ?)
      ''',
      <Object?>[
        envelope.eventId,
        direction,
        envelope.businessId,
        envelope.shopId,
        envelope.originDeviceId,
        envelope.entityType.value,
        envelope.entityId,
        envelope.operation.value,
        envelope.hlc,
        envelope.encode(),
        status,
        envelope.createdAt,
        now,
      ],
    );
  }

  Future<void> _writeCustomerFieldVersions(
    Transaction transaction, {
    required String entityId,
    required String hlc,
    required String originDeviceId,
  }) async {
    for (final field in _customerFields) {
      await _writeFieldVersion(
        transaction,
        entityType: LocalSyncEntityType.customer.value,
        entityId: entityId,
        fieldName: field,
        hlc: hlc,
        originDeviceId: originDeviceId,
      );
    }
  }

  Future<void> _writeFieldVersion(
    Transaction transaction, {
    required String entityType,
    required String entityId,
    required String fieldName,
    required String hlc,
    required String originDeviceId,
  }) async {
    await transaction.rawInsert(
      '''
      INSERT INTO local_sync_field_versions (
        entity_type, entity_id, field_name, hlc, origin_device_id, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(entity_type, entity_id, field_name) DO UPDATE SET
        hlc = excluded.hlc,
        origin_device_id = excluded.origin_device_id,
        updated_at = excluded.updated_at
      ''',
      <Object?>[entityType, entityId, fieldName, hlc, originDeviceId, _now()],
    );
  }

  Future<void> _writeEntityVersion(
    Transaction transaction,
    LocalSyncEnvelope envelope,
  ) async {
    await transaction.rawInsert(
      '''
      INSERT INTO local_sync_entity_versions (
        entity_type, entity_id, hlc, origin_device_id, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(entity_type, entity_id) DO UPDATE SET
        hlc = excluded.hlc,
        origin_device_id = excluded.origin_device_id,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        envelope.entityType.value,
        envelope.entityId,
        envelope.hlc,
        envelope.originDeviceId,
        _now(),
      ],
    );
  }

  Future<String> _readEntityHlc(
    Transaction transaction,
    String entityType,
    String entityId,
  ) async {
    final rows = await transaction.rawQuery(
      '''
      SELECT hlc FROM local_sync_entity_versions
      WHERE entity_type = ? AND entity_id = ? LIMIT 1
      ''',
      <Object?>[entityType, entityId],
    );
    return rows.isEmpty ? '' : '${rows.single['hlc']}';
  }

  Future<bool> _hasCustomerWithSameMobile(
    Transaction transaction, {
    required String customerId,
    required String mobileNo,
  }) async {
    final rows = await transaction.rawQuery(
      '''
      SELECT 1
      FROM hosted_customers
      WHERE customer_id != ?
        AND REPLACE(REPLACE(REPLACE(TRIM(mobile_no), ' ', ''), '-', ''), '+', '') = ?
      LIMIT 1
      ''',
      <Object?>[customerId, _normalizePhone(mobileNo)],
    );
    return rows.isNotEmpty;
  }

  Future<void> _insertConflict(
    Transaction transaction, {
    required LocalSyncEnvelope envelope,
    required String localHlc,
    required String reason,
    required Map<String, Object?> details,
  }) async {
    await transaction.rawInsert(
      '''
      INSERT INTO local_sync_conflicts (
        event_id, entity_type, entity_id, local_hlc, incoming_hlc,
        reason, details_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        envelope.eventId,
        envelope.entityType.value,
        envelope.entityId,
        localHlc,
        envelope.hlc,
        reason,
        canonicalJsonEncode(details),
        _now(),
      ],
    );
  }

  String _saleFingerprint(HostedSaleRecord sale) {
    return canonicalJsonEncode(<String, Object?>{
      'sale_id': sale.saleId,
      'customer_id': sale.customerId,
      'customer_name': sale.customerName,
      'posting_date': sale.postingDate,
      'total_amount': sale.totalAmount,
      'items': sale.items
          .map((HostedSaleLine item) => item.toJson())
          .toList(growable: false),
    });
  }

  String _normalizePhone(String value) {
    return value.trim().replaceAll(RegExp(r'[\s+\-]'), '');
  }

  void _validateEnvelope(
    LocalSyncEnvelope envelope, {
    required LocalSyncEntityType expectedType,
    required String expectedEntityId,
  }) {
    if (envelope.entityType != expectedType ||
        envelope.entityId != expectedEntityId) {
      throw ArgumentError('The sync envelope does not match its entity.');
    }
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
