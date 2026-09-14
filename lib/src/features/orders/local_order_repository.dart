import 'package:sqflite/sqflite.dart';

import 'order_models.dart';

class LocalOrderRepository {
  LocalOrderRepository(this.database);

  final Database database;

  Future<void> saveParkedOrder(LocalOrder order) async {
    await database.transaction((Transaction transaction) async {
      await transaction.insert(
        'orders',
        order.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.insert('parked_orders', <String, Object?>{
        'client_order_id': order.clientOrderId,
        'customer_id': order.customerId,
        'payload_json': order.payloadJson,
        'updated_at': order.updatedAtIso,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> enqueueSubmit(LocalOrder order) async {
    await database.transaction((Transaction transaction) async {
      await transaction.insert(
        'orders',
        order.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.insert('sync_queue', <String, Object?>{
        'client_order_id': order.clientOrderId,
        'action': 'submit_sales_order',
        'payload_json': order.payloadJson,
        'status': 'queued',
        'created_at': order.updatedAtIso,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> markSynced(String clientOrderId, String remoteOrderId) async {
    await database.transaction((Transaction transaction) async {
      await transaction.update(
        'orders',
        <String, Object?>{'status': 'synced', 'remote_order_id': remoteOrderId},
        where: 'client_order_id = ?',
        whereArgs: <Object?>[clientOrderId],
      );
      await transaction.delete(
        'parked_orders',
        where: 'client_order_id = ?',
        whereArgs: <Object?>[clientOrderId],
      );
      await transaction.update(
        'sync_queue',
        <String, Object?>{'status': 'done'},
        where: 'client_order_id = ?',
        whereArgs: <Object?>[clientOrderId],
      );
    });
  }

  Future<int> parkedOrderCount() async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS total FROM parked_orders',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> queuedOrderCount() async {
    final rows = await database.rawQuery(
      "SELECT COUNT(*) AS total FROM sync_queue WHERE status IN ('queued', 'retry')",
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<SyncQueueEntry>> readPendingQueue() async {
    final rows = await database.query(
      'sync_queue',
      where: "status IN ('queued', 'retry')",
      orderBy: 'queue_id ASC',
    );
    return rows
        .map(
          (Map<String, Object?> row) => SyncQueueEntry(
            clientOrderId: '${row['client_order_id']}',
            action: '${row['action']}',
            status: '${row['status']}',
            payloadJson: '${row['payload_json']}',
            createdAtIso: '${row['created_at']}',
          ),
        )
        .toList(growable: false);
  }

  Future<void> markRetry(String clientOrderId) async {
    await database.update(
      'sync_queue',
      <String, Object?>{'status': 'retry'},
      where: 'client_order_id = ?',
      whereArgs: <Object?>[clientOrderId],
    );
  }

  Future<List<LocalOrder>> listParkedOrders() async {
    final rows = await database.rawQuery('''
      SELECT orders.client_order_id, orders.customer_id, orders.total_amount,
             orders.status, orders.payload_json, orders.remote_order_id,
             orders.updated_at
      FROM orders
      INNER JOIN parked_orders
        ON parked_orders.client_order_id = orders.client_order_id
      ORDER BY orders.updated_at DESC
      ''');
    return rows
        .map((Map<String, Object?> row) => LocalOrder.fromRow(row))
        .toList(growable: false);
  }

  Future<List<LocalOrder>> listOrders() async {
    final rows = await database.query('orders', orderBy: 'updated_at DESC');
    return rows
        .map((Map<String, Object?> row) => LocalOrder.fromRow(row))
        .toList(growable: false);
  }

  Future<void> deleteParkedOrder(String clientOrderId) async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete(
        'parked_orders',
        where: 'client_order_id = ?',
        whereArgs: <Object?>[clientOrderId],
      );
      await transaction.delete(
        'orders',
        where: 'client_order_id = ? AND status = ?',
        whereArgs: <Object?>[clientOrderId, 'parked'],
      );
      await transaction.delete(
        'sync_queue',
        where: 'client_order_id = ?',
        whereArgs: <Object?>[clientOrderId],
      );
    });
  }

  Future<void> clearAll() async {
    await database.transaction((Transaction transaction) async {
      await transaction.delete('orders');
      await transaction.delete('parked_orders');
      await transaction.delete('sync_queue');
    });
  }

  Future<void> pruneSyncedOrders(DateTime cutoff) async {
    final cutoffIso = cutoff.toIso8601String();
    await database.delete(
      'orders',
      where: "status = 'synced' AND updated_at < ?",
      whereArgs: <Object?>[cutoffIso],
    );
  }
}
