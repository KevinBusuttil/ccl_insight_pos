import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('allows enough time for first-run mobile schema creation', () {
    expect(neuradixDatabaseOpenTimeout, const Duration(seconds: 60));
  });

  test('creates the expected SQLite tables', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();

    final rows = await openedDatabase.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames =
        rows.map((Map<String, Object?> row) => '${row['name']}').toSet();

    for (final tableName in NeuradixDatabase.expectedTables) {
      expect(tableNames, contains(tableName));
    }

    await database.close();
  });

  test('creates the hosted inventory barcode column', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();

    final rows = await openedDatabase.rawQuery(
      'PRAGMA table_info(hosted_inventory_items)',
    );
    final columnNames =
        rows.map((Map<String, Object?> row) => '${row['name']}').toSet();

    expect(columnNames, contains('barcode'));

    await database.close();
  });

  test(
    'creates local sync tables and immutable sale snapshot columns',
    () async {
      sqfliteFfiInit();
      final database = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final openedDatabase = await database.open();

      final tableRows = await openedDatabase.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames =
          tableRows.map((Map<String, Object?> row) => '${row['name']}').toSet();
      final saleItemRows = await openedDatabase.rawQuery(
        'PRAGMA table_info(hosted_sale_items)',
      );
      final saleItemColumns =
          saleItemRows
              .map((Map<String, Object?> row) => '${row['name']}')
              .toSet();

      expect(tableNames, contains('local_sync_events'));
      expect(tableNames, contains('local_sync_field_versions'));
      expect(tableNames, contains('local_sync_conflicts'));
      expect(
        saleItemColumns,
        containsAll(<String>[
          'sku',
          'barcode',
          'discount_amount',
          'tax_amount',
        ]),
      );

      await database.close();
    },
  );

  test('upgrades a legacy catalog cache schema with the new columns', () async {
    sqfliteFfiInit();
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'neuradix_pos_legacy_upgrade.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);

    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE catalog_categories (
              category_id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              payload_json TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE catalog_items (
              item_id TEXT PRIMARY KEY,
              category_id TEXT NOT NULL,
              display_name TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await legacyDatabase.close();

    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final openedDatabase = await database.open();

    final rows = await openedDatabase.rawQuery(
      'PRAGMA table_info(catalog_items)',
    );
    final columnNames =
        rows.map((Map<String, Object?> row) => '${row['name']}').toSet();

    expect(columnNames, contains('image_url'));
    expect(columnNames, contains('image_version'));
    expect(columnNames, contains('local_image_path'));
    expect(columnNames, contains('price'));
    expect(columnNames, contains('stock_qty'));
    expect(columnNames, contains('pricing_snapshot_json'));

    await database.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('upgrades hosted inventory cache with barcode column', () async {
    sqfliteFfiInit();
    final databasePath = path.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'neuradix_pos_hosted_inventory_upgrade.db',
    );
    await databaseFactoryFfi.deleteDatabase(databasePath);

    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE hosted_inventory_items (
              item_id TEXT PRIMARY KEY,
              sku TEXT NOT NULL,
              display_name TEXT NOT NULL,
              image_url TEXT NOT NULL,
              price REAL NOT NULL,
              stock_qty REAL NOT NULL,
              is_active INTEGER NOT NULL,
              payload_json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await legacyDatabase.close();

    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final openedDatabase = await database.open();

    final rows = await openedDatabase.rawQuery(
      'PRAGMA table_info(hosted_inventory_items)',
    );
    final columnNames =
        rows.map((Map<String, Object?> row) => '${row['name']}').toSet();

    expect(columnNames, contains('barcode'));

    await database.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });
}
