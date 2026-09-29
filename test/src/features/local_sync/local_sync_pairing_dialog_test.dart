import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_pairing_dialog.dart';

void main() {
  testWidgets('returns the entered pairing code after the dialog is removed', (
    WidgetTester tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (BuildContext context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showLocalSyncPairingApprovalDialog(context);
                  },
                  child: const Text('Open pairing'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open pairing'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('local-sync-pairing-code-input')),
      'pairing-code',
    );
    await tester.tap(find.byKey(const Key('approve-local-sync-pairing')));
    await tester.pumpAndSettle();

    expect(result, 'pairing-code');
    expect(find.text('Approve New Register'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
