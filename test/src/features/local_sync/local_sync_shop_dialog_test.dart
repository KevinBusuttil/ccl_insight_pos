import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_shop_dialog.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_models.dart';

void main() {
  testWidgets('returns a trimmed shop without route disposal errors', (
    WidgetTester tester,
  ) async {
    LocalSyncShopDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showCreateLocalSyncShopDialog(context);
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('create-shop-name')),
      '  ABP Shop B  ',
    );
    await tester.enterText(
      find.byKey(const Key('create-shop-code')),
      '  ABP-B  ',
    );
    await tester.tap(find.byKey(const Key('create-shop-submit')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result?.name, 'ABP Shop B');
    expect(result?.code, 'ABP-B');
    expect(find.text('Create Shop'), findsNothing);
  });

  testWidgets('returns the shop selected for register enrollment', (
    WidgetTester tester,
  ) async {
    LocalSyncShop? result;
    const shops = <LocalSyncShop>[
      LocalSyncShop(
        shopId: 'SHOP-A',
        shopName: 'ABP Shop A',
        shopCode: 'ABP-A',
        status: 'active',
        isDefault: true,
      ),
      LocalSyncShop(
        shopId: 'SHOP-B',
        shopName: 'ABP Shop B',
        shopCode: 'ABP-B',
        status: 'active',
        isDefault: false,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showSelectLocalSyncShopDialog(context, shops);
                },
                child: const Text('Open Selector'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open Selector'));
    await tester.pumpAndSettle();
    expect(find.text('Assign This Register'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enrollment-shop-SHOP-B')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result?.shopId, 'SHOP-B');
    expect(find.text('Assign This Register'), findsNothing);
  });
}
