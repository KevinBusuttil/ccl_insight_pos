import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/orders/local_order_repository.dart';
import 'package:neuradix_pos/src/features/orders/order_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores parked orders and sync queue lifecycle', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();
    final repository = LocalOrderRepository(openedDatabase);
    const order = LocalOrder(
      clientOrderId: 'ORDER-001',
      customerId: 'CUST-001',
      totalAmount: 48.50,
      payloadJson: '{"items":[{"item_code":"ITEM-001","qty":2}]}',
      status: 'parked',
      updatedAtIso: '2026-06-07T10:00:00Z',
    );

    await repository.saveParkedOrder(order);
    expect(await repository.parkedOrderCount(), 1);
    expect(
      (await repository.listParkedOrders()).single.clientOrderId,
      'ORDER-001',
    );

    await repository.enqueueSubmit(order);
    expect(await repository.queuedOrderCount(), 1);
    expect(
      (await repository.readPendingQueue()).single.clientOrderId,
      'ORDER-001',
    );

    await repository.markSynced('ORDER-001', 'SO-0001');
    expect(await repository.parkedOrderCount(), 0);
    expect(await repository.queuedOrderCount(), 0);
    expect((await repository.listOrders()).single.remoteOrderId, 'SO-0001');

    await database.close();
  });
}
