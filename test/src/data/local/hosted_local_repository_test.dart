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
              displayName: 'Classic Blend Beans',
              qty: 2,
              rate: 11.5,
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

      await database.close();
    },
  );
}
