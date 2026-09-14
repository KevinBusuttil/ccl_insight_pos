import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/hosted/hosted_models.dart';

class HostedLocalRepository {
  HostedLocalRepository(this.database);

  final Database database;

  Future<void> saveBusinessProfile(HostedBusinessProfile profile) async {
    await database.insert(
      'hosted_business_profile',
      profile.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<HostedBusinessProfile?> readBusinessProfile() async {
    final rows = await database.query(
      'hosted_business_profile',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final payload = Map<String, dynamic>.from(
      jsonDecode('${rows.single['payload_json']}') as Map,
    );
    return HostedBusinessProfile.fromJson(payload);
  }

  Future<void> replaceInventoryItems(List<HostedInventoryItem> items) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete('hosted_inventory_items');
      final batch = transaction.batch();
      for (final item in items) {
        batch.insert('hosted_inventory_items', item.toRow());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<HostedInventoryItem>> listInventoryItems() async {
    final rows = await database.query(
      'hosted_inventory_items',
      where: 'is_active = 1',
      orderBy: 'display_name ASC',
    );
    return rows
        .map((Map<String, Object?> row) => HostedInventoryItem.fromRow(row))
        .toList(growable: false);
  }

  Future<void> upsertInventoryItem(HostedInventoryItem item) async {
    await database.insert(
      'hosted_inventory_items',
      item.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteInventoryItem(String itemId) async {
    await database.delete(
      'hosted_inventory_items',
      where: 'item_id = ?',
      whereArgs: <Object?>[itemId],
    );
  }

  Future<void> replaceCustomers(List<HostedCustomer> customers) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete('hosted_customers');
      final batch = transaction.batch();
      for (final customer in customers) {
        batch.insert('hosted_customers', customer.toRow());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<HostedCustomer>> listCustomers() async {
    final rows = await database.query(
      'hosted_customers',
      where: 'is_active = 1',
      orderBy: 'display_name ASC',
    );
    return rows
        .map((Map<String, Object?> row) => HostedCustomer.fromRow(row))
        .toList(growable: false);
  }

  Future<void> upsertCustomer(HostedCustomer customer) async {
    await database.insert(
      'hosted_customers',
      customer.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveSale(HostedSaleRecord sale) async {
    await database.transaction((Transaction transaction) async {
      await transaction.insert(
        'hosted_sales',
        sale.toSaleRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'hosted_sale_items',
        where: 'sale_id = ?',
        whereArgs: <Object?>[sale.saleId],
      );
      final batch = transaction.batch();
      for (final item in sale.items) {
        batch.insert('hosted_sale_items', <String, Object?>{
          'sale_id': sale.saleId,
          'item_id': item.itemId,
          'display_name': item.displayName,
          'qty': item.qty,
          'rate': item.rate,
          'amount': item.amount,
          'notes': item.notes,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<HostedSaleRecord>> listSales() async {
    final saleRows = await database.query(
      'hosted_sales',
      orderBy: 'posting_date DESC, updated_at DESC',
    );
    if (saleRows.isEmpty) {
      return const <HostedSaleRecord>[];
    }
    final saleIds = saleRows
        .map((Map<String, Object?> row) => '${row['sale_id']}')
        .toList(growable: false);
    final itemRows = await database.query(
      'hosted_sale_items',
      where:
          'sale_id IN (${List<String>.filled(saleIds.length, '?').join(',')})',
      whereArgs: saleIds,
      orderBy: 'sale_id ASC, item_id ASC',
    );
    final itemsBySale = <String, List<HostedSaleLine>>{};
    for (final row in itemRows) {
      itemsBySale
          .putIfAbsent('${row['sale_id']}', () => <HostedSaleLine>[])
          .add(
            HostedSaleLine(
              itemId: '${row['item_id']}',
              displayName: '${row['display_name']}',
              qty: double.tryParse('${row['qty'] ?? 0}') ?? 0,
              rate: double.tryParse('${row['rate'] ?? 0}') ?? 0,
              notes: '${row['notes'] ?? ''}',
            ),
          );
    }

    return saleRows
        .map((Map<String, Object?> row) {
          final payload = Map<String, dynamic>.from(
            jsonDecode('${row['payload_json']}') as Map,
          );
          payload['items'] =
              itemsBySale['${row['sale_id']}']
                  ?.map((HostedSaleLine item) => item.toJson())
                  .toList(growable: false) ??
              const <Map<String, Object?>>[];
          payload['sale_id'] = '${row['sale_id']}';
          payload['remote_sale_id'] = '${row['remote_sale_id']}';
          payload['status'] = '${row['status']}';
          payload['updated_at'] = '${row['updated_at']}';
          return HostedSaleRecord.fromJson(payload);
        })
        .toList(growable: false);
  }

  Future<List<HostedSaleRecord>> listPendingSales() async {
    final rows = await database.query(
      'hosted_sales',
      where: "status IN ('queued', 'local_only')",
      orderBy: 'posting_date ASC, updated_at ASC',
    );
    if (rows.isEmpty) {
      return const <HostedSaleRecord>[];
    }
    final sales = await listSales();
    final pendingIds =
        rows.map((Map<String, Object?> row) => '${row['sale_id']}').toSet();
    return sales
        .where((HostedSaleRecord sale) => pendingIds.contains(sale.saleId))
        .toList(growable: false);
  }

  Future<void> markSaleSynced({
    required String saleId,
    required String remoteSaleId,
  }) async {
    await database.update(
      'hosted_sales',
      <String, Object?>{
        'remote_sale_id': remoteSaleId,
        'status': 'submitted',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'sale_id = ?',
      whereArgs: <Object?>[saleId],
    );
  }

  Future<void> saveUpgradeBatch({
    required String batchId,
    required String status,
    required Map<String, Object?> payload,
  }) async {
    final now = DateTime.now().toIso8601String();
    await database.insert('hosted_upgrade_batches', <String, Object?>{
      'batch_id': batchId,
      'status': status,
      'payload_json': jsonEncode(payload),
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearHostedData() async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete('hosted_business_profile');
      await transaction.delete('hosted_inventory_items');
      await transaction.delete('hosted_customers');
      await transaction.delete('hosted_sales');
      await transaction.delete('hosted_sale_items');
      await transaction.delete('hosted_upgrade_batches');
    });
  }
}
