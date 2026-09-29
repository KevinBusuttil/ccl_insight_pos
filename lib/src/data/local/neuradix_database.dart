import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'neuradix_database_factory_io.dart'
    if (dart.library.js_interop) 'neuradix_database_factory_web.dart';

const Duration neuradixDatabaseOpenTimeout = Duration(seconds: 60);

class NeuradixDatabase {
  NeuradixDatabase({
    DatabaseFactory? databaseFactoryOverride,
    this.databaseName = 'neuradix_pos.db',
    this.databasePath,
  }) : _databaseFactoryOverride = databaseFactoryOverride;

  final DatabaseFactory? _databaseFactoryOverride;
  final String databaseName;
  final String? databasePath;
  Database? _database;
  String? _resolvedPath;

  static const int schemaVersion = 6;
  static const List<String> expectedTables = <String>[
    'app_config',
    'customers',
    'catalog_categories',
    'catalog_items',
    'visit_plan_entries',
    'customer_price_snapshots',
    'customer_policy_snapshots',
    'catalog_image_manifest',
    'sync_state',
    'orders',
    'parked_orders',
    'sync_queue',
    'hosted_business_profile',
    'hosted_inventory_items',
    'hosted_customers',
    'hosted_sales',
    'hosted_sale_items',
    'hosted_upgrade_batches',
    'local_sync_profile',
    'local_sync_peers',
    'local_sync_events',
    'local_sync_event_receipts',
    'local_sync_entity_versions',
    'local_sync_field_versions',
    'local_sync_conflicts',
  ];

  Future<Database> open() async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final factory = _databaseFactoryOverride ?? _resolveFactory();
    final resolvedPath = await _resolveDatabasePath(factory);
    final database = await factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    await _ensureCurrentSchema(database);
    _database = database;
    _resolvedPath = resolvedPath;
    return database;
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null && database.isOpen) {
      await database.close();
    }
  }

  Future<void> reset() async {
    await close();
    final factory = _databaseFactoryOverride ?? _resolveFactory();
    final resolvedPath = _resolvedPath ?? await _resolveDatabasePath(factory);
    await factory.deleteDatabase(resolvedPath);
    _resolvedPath = null;
  }

  DatabaseFactory _resolveFactory() {
    return resolveDatabaseFactory();
  }

  Future<String> _resolveDatabasePath(DatabaseFactory factory) async {
    return databasePath ??
        path.join(await factory.getDatabasesPath(), databaseName);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_config (
        config_key TEXT PRIMARY KEY,
        config_value TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE customers (
        customer_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        mobile_no TEXT,
        payload_json TEXT NOT NULL
      )
      ''');
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
        display_name TEXT NOT NULL,
        image_url TEXT NOT NULL,
        image_version TEXT NOT NULL,
        local_image_path TEXT NOT NULL,
        price REAL NOT NULL,
        stock_qty REAL NOT NULL,
        pricing_snapshot_json TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE visit_plan_entries (
        entry_id TEXT PRIMARY KEY,
        visit_date TEXT NOT NULL,
        sales_rep TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        customer_code TEXT NOT NULL,
        sequence_no INTEGER NOT NULL,
        status TEXT NOT NULL,
        notes TEXT NOT NULL,
        starts_on TEXT,
        ends_on TEXT,
        payload_json TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE customer_price_snapshots (
        sync_date TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        item_code TEXT NOT NULL,
        price REAL NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (sync_date, customer_id, item_code)
      )
      ''');
    await db.execute('''
      CREATE TABLE customer_policy_snapshots (
        sync_date TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (sync_date, customer_id)
      )
      ''');
    await db.execute('''
      CREATE TABLE catalog_image_manifest (
        item_id TEXT PRIMARY KEY,
        image_url TEXT NOT NULL,
        image_version TEXT NOT NULL,
        local_path TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE sync_state (
        state_key TEXT PRIMARY KEY,
        state_value TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE orders (
        client_order_id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        remote_order_id TEXT,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE parked_orders (
        client_order_id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        queue_id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_order_id TEXT NOT NULL UNIQUE,
        action TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE hosted_business_profile (
        business_id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE hosted_inventory_items (
        item_id TEXT PRIMARY KEY,
        sku TEXT NOT NULL,
        barcode TEXT NOT NULL,
        display_name TEXT NOT NULL,
        image_url TEXT NOT NULL,
        price REAL NOT NULL,
        stock_qty REAL NOT NULL,
        is_active INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE hosted_customers (
        customer_id TEXT PRIMARY KEY,
        customer_code TEXT NOT NULL,
        display_name TEXT NOT NULL,
        mobile_no TEXT NOT NULL,
        email_id TEXT NOT NULL,
        primary_address TEXT NOT NULL,
        is_active INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE hosted_sales (
        sale_id TEXT PRIMARY KEY,
        remote_sale_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        posting_date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE hosted_sale_items (
        sale_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        sku TEXT NOT NULL,
        barcode TEXT NOT NULL,
        display_name TEXT NOT NULL,
        qty REAL NOT NULL,
        rate REAL NOT NULL,
        discount_amount REAL NOT NULL,
        tax_amount REAL NOT NULL,
        amount REAL NOT NULL,
        notes TEXT NOT NULL,
        PRIMARY KEY (sale_id, item_id)
      )
      ''');
    await db.execute('''
      CREATE TABLE hosted_upgrade_batches (
        batch_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await _createLocalSyncTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion == newVersion) {
      return;
    }
    if (oldVersion < 2) {
      await _migrateToVersion2(db);
    }
    if (oldVersion < 3) {
      await _migrateToVersion3(db);
    }
    if (oldVersion < 4) {
      await _migrateToVersion4(db);
    }
    if (oldVersion < 5) {
      await _migrateToVersion5(db);
    }
    if (oldVersion < 6) {
      await _migrateToVersion6(db);
    }
    await _ensureCurrentSchema(db);
  }

  Future<void> _migrateToVersion2(Database db) async {
    await _ensureColumn(
      db,
      'catalog_categories',
      'display_name',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'catalog_categories',
      'payload_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    await _ensureColumn(
      db,
      'catalog_items',
      'image_url',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'catalog_items',
      'price',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'catalog_items',
      'stock_qty',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'catalog_items',
      'pricing_snapshot_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
  }

  Future<void> _migrateToVersion3(Database db) async {
    await _ensureColumn(
      db,
      'catalog_items',
      'image_version',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'catalog_items',
      'local_image_path',
      "TEXT NOT NULL DEFAULT ''",
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visit_plan_entries (
        entry_id TEXT PRIMARY KEY,
        visit_date TEXT NOT NULL,
        sales_rep TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        customer_code TEXT NOT NULL,
        sequence_no INTEGER NOT NULL,
        status TEXT NOT NULL,
        notes TEXT NOT NULL,
        starts_on TEXT,
        ends_on TEXT,
        payload_json TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_price_snapshots (
        sync_date TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        item_code TEXT NOT NULL,
        price REAL NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (sync_date, customer_id, item_code)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_policy_snapshots (
        sync_date TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (sync_date, customer_id)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_image_manifest (
        item_id TEXT PRIMARY KEY,
        image_url TEXT NOT NULL,
        image_version TEXT NOT NULL,
        local_path TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        state_key TEXT PRIMARY KEY,
        state_value TEXT NOT NULL
      )
      ''');
  }

  Future<void> _migrateToVersion4(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hosted_business_profile (
        business_id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hosted_inventory_items (
        item_id TEXT PRIMARY KEY,
        sku TEXT NOT NULL,
        barcode TEXT NOT NULL,
        display_name TEXT NOT NULL,
        image_url TEXT NOT NULL,
        price REAL NOT NULL,
        stock_qty REAL NOT NULL,
        is_active INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hosted_customers (
        customer_id TEXT PRIMARY KEY,
        customer_code TEXT NOT NULL,
        display_name TEXT NOT NULL,
        mobile_no TEXT NOT NULL,
        email_id TEXT NOT NULL,
        primary_address TEXT NOT NULL,
        is_active INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hosted_sales (
        sale_id TEXT PRIMARY KEY,
        remote_sale_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        posting_date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hosted_sale_items (
        sale_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        sku TEXT NOT NULL DEFAULT '',
        barcode TEXT NOT NULL DEFAULT '',
        display_name TEXT NOT NULL,
        qty REAL NOT NULL,
        rate REAL NOT NULL,
        discount_amount REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        amount REAL NOT NULL,
        notes TEXT NOT NULL,
        PRIMARY KEY (sale_id, item_id)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hosted_upgrade_batches (
        batch_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
  }

  Future<void> _migrateToVersion5(Database db) async {
    await _ensureColumn(
      db,
      'hosted_inventory_items',
      'barcode',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _migrateToVersion6(Database db) async {
    await _ensureColumn(
      db,
      'hosted_sale_items',
      'sku',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'hosted_sale_items',
      'barcode',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'hosted_sale_items',
      'discount_amount',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'hosted_sale_items',
      'tax_amount',
      'REAL NOT NULL DEFAULT 0',
    );
    await _createLocalSyncTables(db);
  }

  Future<void> _ensureCurrentSchema(Database db) async {
    await _createMissingTables(db);
    await _migrateToVersion2(db);
    await _migrateToVersion3(db);
    await _migrateToVersion4(db);
    await _migrateToVersion5(db);
    await _migrateToVersion6(db);
  }

  Future<void> _createMissingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_config (
        config_key TEXT PRIMARY KEY,
        config_value TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        customer_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        mobile_no TEXT,
        payload_json TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_categories (
        category_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        payload_json TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_items (
        item_id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        image_url TEXT NOT NULL,
        image_version TEXT NOT NULL,
        local_image_path TEXT NOT NULL,
        price REAL NOT NULL,
        stock_qty REAL NOT NULL,
        pricing_snapshot_json TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visit_plan_entries (
        entry_id TEXT PRIMARY KEY,
        visit_date TEXT NOT NULL,
        sales_rep TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        customer_code TEXT NOT NULL,
        sequence_no INTEGER NOT NULL,
        status TEXT NOT NULL,
        notes TEXT NOT NULL,
        starts_on TEXT,
        ends_on TEXT,
        payload_json TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_price_snapshots (
        sync_date TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        item_code TEXT NOT NULL,
        price REAL NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (sync_date, customer_id, item_code)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_policy_snapshots (
        sync_date TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY (sync_date, customer_id)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_image_manifest (
        item_id TEXT PRIMARY KEY,
        image_url TEXT NOT NULL,
        image_version TEXT NOT NULL,
        local_path TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        state_key TEXT PRIMARY KEY,
        state_value TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        client_order_id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        remote_order_id TEXT,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parked_orders (
        client_order_id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        queue_id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_order_id TEXT NOT NULL UNIQUE,
        action TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
      ''');
    await _createLocalSyncTables(db);
  }

  Future<void> _createLocalSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_profile (
        profile_id INTEGER PRIMARY KEY,
        business_id TEXT NOT NULL,
        shop_id TEXT NOT NULL,
        shop_name TEXT NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        relay_url TEXT NOT NULL,
        protocol_version INTEGER NOT NULL,
        key_epoch INTEGER NOT NULL,
        is_preferred_peer INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_peers (
        device_id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        signing_public_key TEXT NOT NULL,
        exchange_public_key TEXT NOT NULL,
        status TEXT NOT NULL,
        key_epoch INTEGER NOT NULL,
        last_seen_at TEXT NOT NULL,
        last_hlc TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_events (
        event_id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        business_id TEXT NOT NULL,
        shop_id TEXT NOT NULL,
        origin_device_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        hlc TEXT NOT NULL,
        envelope_json TEXT NOT NULL,
        status TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_event_receipts (
        event_id TEXT NOT NULL,
        peer_device_id TEXT NOT NULL,
        acknowledged_at TEXT NOT NULL,
        PRIMARY KEY (event_id, peer_device_id)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_entity_versions (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        hlc TEXT NOT NULL,
        origin_device_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_field_versions (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        hlc TEXT NOT NULL,
        origin_device_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id, field_name)
      )
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_conflicts (
        conflict_id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        local_hlc TEXT NOT NULL,
        incoming_hlc TEXT NOT NULL,
        reason TEXT NOT NULL,
        details_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
      ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_sync_events_pending
      ON local_sync_events(direction, status, hlc)
      ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_sync_events_entity
      ON local_sync_events(entity_type, entity_id, hlc)
      ''');
  }

  Future<void> _ensureColumn(
    Database db,
    String tableName,
    String columnName,
    String definition,
  ) async {
    if (!await _tableExists(db, tableName)) {
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = columns.any(
      (Map<String, Object?> row) => '${row['name']}' == columnName,
    );
    if (hasColumn) {
      return;
    }

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
