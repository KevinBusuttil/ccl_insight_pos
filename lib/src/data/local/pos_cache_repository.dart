import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/pos/pos_debug_log.dart';
import '../../features/pos/pos_models.dart';

class PosCacheRepository {
  PosCacheRepository(this.database);

  final Database database;

  String get databasePath => database.path;

  Future<void> replaceCustomers(List<PosCustomer> customers) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete('customers');
      final batch = transaction.batch();
      for (final customer in customers) {
        batch.insert('customers', customer.toRow());
      }
      await batch.commit(noResult: true);
    });
    PosDebugLog.info(
      'cache.replaceCustomers',
      PosDebugLog.summarizeCustomers(customers),
    );
  }

  Future<List<PosCustomer>> searchCustomers(String searchText) async {
    final normalizedSearch = searchText.trim().toLowerCase();
    final rows = await database.rawQuery(
      '''
      SELECT customer_id, display_name, mobile_no, payload_json
      FROM customers
      WHERE (? = '')
         OR LOWER(display_name) LIKE ?
         OR LOWER(COALESCE(mobile_no, '')) LIKE ?
      ORDER BY display_name ASC
      ''',
      <Object?>[normalizedSearch, '%$normalizedSearch%', '%$normalizedSearch%'],
    );
    final customers = rows
        .map((Map<String, Object?> row) => PosCustomer.fromRow(row))
        .toList(growable: false);
    PosDebugLog.info(
      'cache.searchCustomers',
      'search="$normalizedSearch" ${PosDebugLog.summarizeCustomers(customers)}',
    );
    return customers;
  }

  Future<void> replaceCatalog(List<PosCatalogGroup> groups) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete('catalog_items');
      await transaction.delete('catalog_categories');

      final batch = transaction.batch();
      for (final group in groups) {
        batch.insert('catalog_categories', <String, Object?>{
          'category_id': group.groupName,
          'display_name': group.groupName,
          'payload_json': jsonEncode(<String, Object?>{
            'item_group': group.groupName,
            'item_group_image': group.groupImageUrl,
          }),
        });
        for (final item in group.items) {
          batch.insert('catalog_items', item.toRow(group.groupName));
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PosCatalogGroup>> readCatalog({
    String searchText = '',
    String? selectedCategory,
    String? syncDate,
    String? customerId,
  }) async {
    final normalizedSearch = searchText.trim().toLowerCase();
    final rows = await database.rawQuery(
      '''
      SELECT
        category.category_id,
        category.display_name AS category_name,
        category.payload_json AS category_payload_json,
        item.item_id,
        item.display_name,
        COALESCE(manifest.image_url, item.image_url, '') AS image_url,
        COALESCE(manifest.image_version, item.image_version, '') AS image_version,
        COALESCE(manifest.local_path, item.local_image_path, '') AS local_image_path,
        COALESCE(price_snapshot.price, item.price) AS price,
        item.stock_qty,
        item.pricing_snapshot_json
      FROM catalog_categories category
      LEFT JOIN catalog_items item
        ON item.category_id = category.category_id
      LEFT JOIN customer_price_snapshots price_snapshot
        ON price_snapshot.item_code = item.item_id
       AND price_snapshot.sync_date = ?
       AND price_snapshot.customer_id = ?
      LEFT JOIN catalog_image_manifest manifest
        ON manifest.item_id = item.item_id
      WHERE (? = '' OR LOWER(category.display_name) LIKE ? OR LOWER(COALESCE(item.display_name, '')) LIKE ?)
        AND (? IS NULL OR category.category_id = ?)
      ORDER BY category.display_name ASC, item.display_name ASC
      ''',
      <Object?>[
        syncDate ?? '',
        customerId ?? '',
        normalizedSearch,
        '%$normalizedSearch%',
        '%$normalizedSearch%',
        selectedCategory,
        selectedCategory,
      ],
    );

    final groupedItems = <String, List<PosCatalogItem>>{};
    final groupImages = <String, String>{};
    for (final row in rows) {
      final categoryName = '${row['category_name']}';
      final categoryPayload = Map<String, dynamic>.from(
        jsonDecode('${row['category_payload_json'] ?? '{}'}') as Map,
      );
      groupImages[categoryName] =
          '${categoryPayload['item_group_image'] ?? ''}';
      final itemId = row['item_id'];
      if (itemId == null) {
        groupedItems.putIfAbsent(categoryName, () => <PosCatalogItem>[]);
        continue;
      }
      groupedItems
          .putIfAbsent(categoryName, () => <PosCatalogItem>[])
          .add(PosCatalogItem.fromRow(row, categoryName));
    }

    return groupedItems.entries
        .map(
          (MapEntry<String, List<PosCatalogItem>> entry) => PosCatalogGroup(
            groupName: entry.key,
            groupImageUrl: groupImages[entry.key] ?? '',
            items: entry.value,
          ),
        )
        .toList(growable: false);
  }

  Future<void> replaceVisitPlanEntriesForWeek(
    String weekStart,
    List<PosVisitPlanEntry> entries,
  ) async {
    final weekEnd = _addDays(weekStart, 6);
    await database.transaction((Transaction transaction) async {
      await transaction.delete(
        'visit_plan_entries',
        where: 'visit_date BETWEEN ? AND ?',
        whereArgs: <Object?>[weekStart, weekEnd],
      );
      final batch = transaction.batch();
      for (final entry in entries) {
        batch.insert('visit_plan_entries', entry.toRow());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> replaceVisitPlanEntriesForDate(
    String syncDate,
    List<PosVisitPlanEntry> entries,
  ) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete(
        'visit_plan_entries',
        where: 'visit_date = ?',
        whereArgs: <Object?>[syncDate],
      );
      final batch = transaction.batch();
      for (final entry in entries) {
        batch.insert('visit_plan_entries', entry.toRow());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PosVisitPlanEntry>> readVisitPlanEntriesForWeek(
    String weekStart,
    String salesRep,
  ) async {
    final weekEnd = _addDays(weekStart, 6);
    final rows = await database.query(
      'visit_plan_entries',
      where: 'visit_date BETWEEN ? AND ? AND sales_rep = ?',
      whereArgs: <Object?>[weekStart, weekEnd, salesRep],
      orderBy: 'visit_date ASC, sequence_no ASC, customer_name ASC',
    );
    return rows
        .map((Map<String, Object?> row) => PosVisitPlanEntry.fromRow(row))
        .toList(growable: false);
  }

  Future<void> saveCustomerPriceSnapshots(
    String syncDate,
    List<PosCustomerPriceSnapshot> snapshots,
  ) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete(
        'customer_price_snapshots',
        where: 'sync_date = ?',
        whereArgs: <Object?>[syncDate],
      );
      final batch = transaction.batch();
      for (final snapshot in snapshots) {
        batch.insert('customer_price_snapshots', snapshot.toRow());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> replaceCustomerPolicySnapshots(
    String syncDate,
    List<PosCustomerPolicy> policies,
  ) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete(
        'customer_policy_snapshots',
        where: 'sync_date = ?',
        whereArgs: <Object?>[syncDate],
      );
      final batch = transaction.batch();
      for (final policy in policies) {
        batch.insert('customer_policy_snapshots', <String, Object?>{
          'sync_date': syncDate,
          'customer_id': policy.customer,
          'payload_json': jsonEncode(<String, Object?>{
            'customer': policy.customer,
            'custom_customer_id': policy.customerCode,
            'is_frozen': policy.isFrozen,
            'minimum_order_amount': policy.minimumOrderAmount,
            'minimum_order_required': policy.minimumOrderRequired,
            'notes_bypass_minimum': policy.notesBypassMinimum,
            'outstanding_amount': policy.outstandingAmount,
            'has_outstanding_documents': policy.hasOutstandingDocuments,
            'same_day_orders': policy.sameDayOrders,
          }),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<PosCustomerPolicy?> readCustomerPolicySnapshot(
    String syncDate,
    String customerId,
  ) async {
    final rows = await database.query(
      'customer_policy_snapshots',
      columns: const <String>['payload_json'],
      where: 'sync_date = ? AND customer_id = ?',
      whereArgs: <Object?>[syncDate, customerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PosCustomerPolicy.fromJson(
      Map<String, dynamic>.from(
        jsonDecode('${rows.single['payload_json']}') as Map,
      ),
    );
  }

  Future<void> upsertImageManifestEntries(
    List<PosImageManifestEntry> entries,
  ) async {
    await database.transaction((Transaction transaction) async {
      final batch = transaction.batch();
      for (final entry in entries) {
        batch.insert(
          'catalog_image_manifest',
          entry.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveDaySyncMetadata({
    required String syncDate,
    required List<String> customerIds,
    required Map<String, String> cursors,
    String? syncedAt,
  }) async {
    final resolvedSyncedAt = syncedAt ?? DateTime.now().toIso8601String();
    await _saveStateValue(
      'day_sync::$syncDate::customers',
      jsonEncode(customerIds),
    );
    await _saveStateValue('day_sync::$syncDate::synced_at', resolvedSyncedAt);
    for (final entry in cursors.entries) {
      await _saveStateValue('cursor::${entry.key}', entry.value);
    }
  }

  Future<String?> readDaySyncSyncedAt(String syncDate) {
    return _readStateValue('day_sync::$syncDate::synced_at');
  }

  Future<List<String>> readDaySyncCustomers(String syncDate) async {
    final value = await _readStateValue('day_sync::$syncDate::customers');
    if (value == null || value.isEmpty) {
      return const <String>[];
    }
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded.map((dynamic row) => '$row').toList(growable: false);
  }

  Future<bool> hasCustomerPriceSync(String syncDate, String customerId) async {
    final rows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM customer_price_snapshots
      WHERE sync_date = ?
        AND customer_id = ?
      ''',
      <Object?>[syncDate, customerId],
    );
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  }

  Future<void> saveHistorySnapshot(List<PosHistoryOrder> history) async {
    await _saveConfigValue(
      'history_snapshot',
      jsonEncode(
        history.map((PosHistoryOrder order) => order.toJson()).toList(),
      ),
    );
  }

  Future<List<PosHistoryOrder>> readHistorySnapshot() async {
    final value = await _readConfigValue('history_snapshot');
    if (value == null || value.isEmpty) {
      return const <PosHistoryOrder>[];
    }
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .map(
          (dynamic row) =>
              PosHistoryOrder.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<void> saveTaxSnapshot(List<Map<String, dynamic>> taxes) async {
    await _saveConfigValue('tax_snapshot', jsonEncode(taxes));
  }

  Future<List<Map<String, dynamic>>> readTaxSnapshot() async {
    final value = await _readConfigValue('tax_snapshot');
    if (value == null || value.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> saveAccountSnapshot(PosAccountSummary summary) async {
    await _saveConfigValue('account_snapshot', jsonEncode(summary.toJson()));
  }

  Future<PosAccountSummary?> readAccountSnapshot() async {
    final value = await _readConfigValue('account_snapshot');
    if (value == null || value.isEmpty) {
      return null;
    }
    return PosAccountSummary.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map),
    );
  }

  Future<void> saveSession(PosLoginSession session) async {
    await _saveConfigValue('session_snapshot', jsonEncode(session.toJson()));
  }

  Future<PosLoginSession?> readSession() async {
    final value = await _readConfigValue('session_snapshot');
    if (value == null || value.isEmpty) {
      return null;
    }
    return PosLoginSession.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map),
    );
  }

  Future<void> clearSession() async {
    await database.delete(
      'app_config',
      where: 'config_key = ?',
      whereArgs: <Object?>['session_snapshot'],
    );
  }

  Future<void> saveIssueStatement(
    String customerId,
    Map<String, dynamic> payload,
  ) async {
    await _saveConfigValue('issue_statement_$customerId', jsonEncode(payload));
  }

  Future<PosIssueStatement?> readIssueStatement(String customerId) async {
    final value = await _readConfigValue('issue_statement_$customerId');
    if (value == null || value.isEmpty) {
      return null;
    }
    return PosIssueStatement.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map),
    );
  }

  Future<void> clearMasterAndTransactionData({
    bool keepBootstrap = true,
  }) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete('customers');
      await transaction.delete('catalog_items');
      await transaction.delete('catalog_categories');
      await transaction.delete('visit_plan_entries');
      await transaction.delete('customer_price_snapshots');
      await transaction.delete('customer_policy_snapshots');
      await transaction.delete('catalog_image_manifest');
      await transaction.delete('sync_state');
      await transaction.delete('orders');
      await transaction.delete('parked_orders');
      await transaction.delete('sync_queue');
      if (keepBootstrap) {
        await transaction.delete(
          'app_config',
          where:
              "config_key NOT IN ('base_url', 'use_ssl', 'brand_name', 'theme_primary', 'theme_secondary', 'theme_accent', 'theme_text_on_primary', 'theme_surface', 'theme_active')",
        );
      } else {
        await transaction.delete('app_config');
      }
    });
  }

  Future<void> _saveConfigValue(String key, String value) async {
    await database.insert('app_config', <String, Object?>{
      'config_key': key,
      'config_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> _readConfigValue(String key) async {
    final rows = await database.query(
      'app_config',
      columns: const <String>['config_value'],
      where: 'config_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return '${rows.single['config_value']}';
  }

  Future<void> _saveStateValue(String key, String value) async {
    await database.insert('sync_state', <String, Object?>{
      'state_key': key,
      'state_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> _readStateValue(String key) async {
    final rows = await database.query(
      'sync_state',
      columns: const <String>['state_value'],
      where: 'state_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return '${rows.single['state_value']}';
  }

  String _addDays(String isoDate, int days) {
    final base = DateTime.parse(isoDate);
    return base.add(Duration(days: days)).toIso8601String().split('T').first;
  }
}
