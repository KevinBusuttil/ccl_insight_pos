import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/hosted_local_repository.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/hosted/hosted_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'persists hosted profile, inventory, customers, and sales locally',
    () async {
      sqfliteFfiInit();
      final database = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final openedDatabase = await database.open();
      final repository = HostedLocalRepository(openedDatabase);

      await repository.saveBusinessProfile(
        const HostedBusinessProfile(
          businessId: 'NBIZ-00001',
          businessName: 'Neuradix Corner Shop',
          slug: 'neuradix-corner-shop',
          ownerUser: 'owner@example.com',
          membershipRole: 'Owner',
          planType: 'free_local',
          subscriptionStatus: 'active',
          deploymentMode: 'neuradix_cloud',
        ),
      );
      await repository.upsertInventoryItem(
        const HostedInventoryItem(
          itemId: 'NPROD-00001',
          sku: 'COFFEE-001',
          barcode: '5353535353',
          displayName: 'Classic Blend Beans',
          imageUrl: '',
          price: 11.5,
          stockQty: 18,
          isActive: true,
        ),
      );
      await repository.upsertCustomer(
        const HostedCustomer(
          customerId: 'NCUST-00001',
          customerCode: 'CUS-001',
          displayName: 'Neighbourhood Grocer',
          mobileNo: '99880011',
          emailId: 'grocer@example.com',
          primaryAddress: 'Valletta',
          isActive: true,
        ),
      );
      await repository.saveSale(
        const HostedSaleRecord(
          saleId: 'local-sale-1',
          remoteSaleId: '',
          customerId: 'NCUST-00001',
          customerName: 'Neighbourhood Grocer',
          postingDate: '2026-08-12',
          totalAmount: 23.0,
          status: 'local_only',
          items: <HostedSaleLine>[
            HostedSaleLine(
              itemId: 'NPROD-00001',
              sku: 'COFFEE-001',
              barcode: '5353535353',
              displayName: 'Classic Blend Beans',
              qty: 2,
              rate: 11.5,
              discountAmount: 1,
              taxAmount: 0.5,
            ),
          ],
        ),
      );

      final profile = await repository.readBusinessProfile();
      final inventory = await repository.listInventoryItems();
      final customers = await repository.listCustomers();
      final sales = await repository.listSales();

      expect(profile?.businessName, 'Neuradix Corner Shop');
      expect(profile?.planType, 'free_local');
      expect(inventory.single.sku, 'COFFEE-001');
      expect(inventory.single.barcode, '5353535353');
      expect(customers.single.displayName, 'Neighbourhood Grocer');
      expect(sales.single.customerName, 'Neighbourhood Grocer');
      expect(sales.single.items.single.qty, 2);
      expect(sales.single.items.single.sku, 'COFFEE-001');
      expect(sales.single.items.single.barcode, '5353535353');
      expect(sales.single.items.single.discountAmount, 1);
      expect(sales.single.items.single.taxAmount, 0.5);

      await database.close();
    },
  );

  test('clears shop inventory without clearing business-wide data', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();
    final repository = HostedLocalRepository(openedDatabase);

    await repository.upsertInventoryItem(
      const HostedInventoryItem(
        itemId: 'SHOP-ITEM-001',
        sku: 'SHOP-001',
        barcode: '590000000001',
        displayName: 'Shop-only item',
        imageUrl: '',
        price: 4.5,
        stockQty: 3,
        isActive: true,
      ),
    );
    await repository.upsertCustomer(
      const HostedCustomer(
        customerId: 'BUSINESS-CUSTOMER-001',
        customerCode: 'CUS-001',
        displayName: 'Shared Customer',
        mobileNo: '',
        emailId: '',
        primaryAddress: '',
        isActive: true,
      ),
    );

    await repository.clearInventoryItems();

    expect(await repository.listInventoryItems(), isEmpty);
    expect(
      (await repository.listCustomers()).single.customerId,
      'BUSINESS-CUSTOMER-001',
    );
    await database.close();
  });

  test(
    'replaces submitted cloud history without discarding pending sales',
    () async {
      sqfliteFfiInit();
      final database = NeuradixDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final openedDatabase = await database.open();
      final repository = HostedLocalRepository(openedDatabase);

      await repository.saveSale(
        const HostedSaleRecord(
          saleId: 'old-submitted',
          remoteSaleId: 'NSALE-OLD',
          customerId: 'NCUST-OLD',
          customerName: 'Old Customer',
          postingDate: '2026-09-27',
          totalAmount: 1,
          status: 'submitted',
          items: <HostedSaleLine>[],
        ),
      );
      await repository.saveSale(
        const HostedSaleRecord(
          saleId: 'pending-local',
          remoteSaleId: '',
          customerId: 'NCUST-PENDING',
          customerName: 'Pending Customer',
          postingDate: '2026-09-28',
          totalAmount: 2,
          status: 'queued',
          items: <HostedSaleLine>[],
        ),
      );

      await repository.replaceSubmittedSales(const <HostedSaleRecord>[
        HostedSaleRecord(
          saleId: 'current-submitted',
          remoteSaleId: 'NSALE-CURRENT',
          customerId: 'NCUST-CURRENT',
          customerName: 'Current Customer',
          postingDate: '2026-09-28',
          totalAmount: 3,
          status: 'submitted',
          items: <HostedSaleLine>[],
        ),
      ]);

      final sales = await repository.listSales();
      expect(
        sales.map((HostedSaleRecord sale) => sale.saleId),
        containsAll(<String>['pending-local', 'current-submitted']),
      );
      expect(
        sales.map((HostedSaleRecord sale) => sale.saleId),
        isNot(contains('old-submitted')),
      );

      await database.close();
    },
  );

  test('clears synced hosted cache when the business changes', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();
    final repository = HostedLocalRepository(openedDatabase);

    await repository.saveBusinessProfile(
      const HostedBusinessProfile(
        businessId: 'NBIZ-OLD',
        businessName: 'Old Business',
        slug: 'old-business',
        ownerUser: 'owner@example.com',
        membershipRole: 'Owner',
        planType: 'free_cloud',
        subscriptionStatus: 'active',
        deploymentMode: 'neuradix_cloud',
      ),
    );
    await repository.saveSale(
      const HostedSaleRecord(
        saleId: 'synced-sale',
        remoteSaleId: 'NSALE-OLD',
        customerId: 'NCUST-OLD',
        customerName: 'Old Customer',
        postingDate: '2026-09-28',
        totalAmount: 2,
        status: 'submitted',
        items: <HostedSaleLine>[],
      ),
    );

    expect(await repository.prepareForBusiness('NBIZ-NEW'), isNull);
    expect(await repository.readBusinessProfile(), isNull);
    expect(await repository.listSales(), isEmpty);

    await database.close();
  });

  test('blocks a business change while local sales are pending', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();
    final repository = HostedLocalRepository(openedDatabase);

    await repository.saveBusinessProfile(
      const HostedBusinessProfile(
        businessId: 'NBIZ-OLD',
        businessName: 'Old Business',
        slug: 'old-business',
        ownerUser: 'owner@example.com',
        membershipRole: 'Owner',
        planType: 'free_cloud',
        subscriptionStatus: 'active',
        deploymentMode: 'neuradix_cloud',
      ),
    );
    await repository.saveSale(
      const HostedSaleRecord(
        saleId: 'pending-sale',
        remoteSaleId: '',
        customerId: 'NCUST-PENDING',
        customerName: 'Pending Customer',
        postingDate: '2026-09-28',
        totalAmount: 2,
        status: 'queued',
        items: <HostedSaleLine>[],
      ),
    );

    final error = await repository.prepareForBusiness('NBIZ-NEW');
    expect(error, contains('1 unsynced or local-only sale'));
    expect((await repository.readBusinessProfile())?.businessId, 'NBIZ-OLD');
    expect(await repository.listSales(), hasLength(1));

    await database.close();
  });
}
