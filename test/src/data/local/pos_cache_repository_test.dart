import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/pos_cache_repository.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/pos/pos_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores and searches customer and catalog cache rows', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();
    final repository = PosCacheRepository(openedDatabase);

    await repository.replaceCustomers(PosPreviewData.customers);
    await repository.replaceCatalog(PosPreviewData.catalog);

    final customers = await repository.searchCustomers('cassar');
    expect(customers, hasLength(1));
    expect(customers.single.displayName, 'Cassar Retail Valletta');

    final byId = await repository.searchCustomers('cust-002');
    expect(byId.single.id, 'CUST-002');

    final catalog = await repository.readCatalog(searchText: 'espresso');
    expect(catalog, hasLength(1));
    expect(catalog.single.items.single.itemCode, 'COFFEE-002');

    await database.close();
  });

  test('overlays day-synced customer prices and stores visit plans', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();
    final repository = PosCacheRepository(openedDatabase);

    await repository.replaceCatalog(PosPreviewData.catalog);
    await repository.saveCustomerPriceSnapshots(
      '2026-06-10',
      const <PosCustomerPriceSnapshot>[
        PosCustomerPriceSnapshot(
          syncDate: '2026-06-10',
          customerId: 'CUST-001',
          customerCode: 'AX-1001',
          itemCode: 'COFFEE-001',
          price: 8.95,
        ),
      ],
    );
    await repository
        .replaceVisitPlanEntriesForWeek('2026-06-08', const <PosVisitPlanEntry>[
          PosVisitPlanEntry(
            id: 'PLAN-001',
            salesRep: 'sara.camilleri',
            customerId: 'CUST-001',
            customerName: 'Cassar Retail Valletta',
            customerCode: 'AX-1001',
            visitDate: '2026-06-10',
            sequenceNo: 1,
            status: 'Planned',
            notes: '',
            startsOn: '',
            endsOn: '',
            modified: '2026-06-10 08:00:00',
          ),
        ]);

    final repricedCatalog = await repository.readCatalog(
      syncDate: '2026-06-10',
      customerId: 'CUST-001',
    );
    final weekPlan = await repository.readVisitPlanEntriesForWeek(
      '2026-06-08',
      'sara.camilleri',
    );

    expect(repricedCatalog.first.items.first.price, 8.95);
    expect(weekPlan, hasLength(1));
    expect(weekPlan.single.customerId, 'CUST-001');

    await database.close();
  });
}
