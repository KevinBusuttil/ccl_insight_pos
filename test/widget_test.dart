import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:neuradix_pos/src/app/neuradix_pos_app.dart';
import 'package:neuradix_pos/src/features/bootstrap/bootstrap_config.dart';
import 'package:neuradix_pos/src/features/pos/pos_models.dart';
import 'package:neuradix_pos/src/theme/neuradix_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('renders the instance setup view', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NeuradixTheme.light(),
        home: const Scaffold(body: NeuradixInstanceSetupPreview()),
      ),
    );

    expect(find.text('Connect Neuradix POS'), findsOneWidget);
    expect(find.text('Preview Tablet UI'), findsOneWidget);
    expect(find.text('Save Instance'), findsOneWidget);
  });

  test('uses the shared cloud bench as the hosted default URL', () {
    expect(neuradixDefaultCloudBaseUrl, neuradixDefaultCloudBaseUrlFallback);
    expect(
      PosPreviewData.bootstrap.defaultCloudBaseUrl,
      neuradixDefaultCloudBaseUrlFallback,
    );
  });

  test(
    'repairs stale hosted configs that still point to the dedicated bench',
    () {
      final repaired = repairHostedCloudConfig(
        const BootstrapConfig(
          baseUrl: 'http://127.0.0.1:8008',
          useSsl: false,
          deploymentMode: 'neuradix_cloud',
          planType: 'free_cloud',
          brandName: 'Neuradix POS',
          supportEmail: 'support@neuradix.local',
          defaultCloudBaseUrl: 'http://neuradix-cloud.localhost:8018',
          themePrimary: '#2B6F77',
          themeSecondary: '#86A96F',
          themeAccent: '#5E6B73',
          themeTextOnPrimary: '#FFFFFF',
          themeSurface: '#F4F7F5',
          themeActive: '#355B66',
        ),
      );

      expect(repaired.baseUrl, neuradixDefaultCloudBaseUrlFallback);
      expect(repaired.defaultCloudBaseUrl, neuradixDefaultCloudBaseUrlFallback);
    },
  );

  test('keeps explicit hosted cloud URLs untouched', () {
    final original = const BootstrapConfig(
      baseUrl: 'https://erp.neuradix.com',
      useSsl: true,
      deploymentMode: 'neuradix_cloud',
      planType: 'free_cloud',
      brandName: 'Neuradix POS',
      supportEmail: 'support@neuradix.local',
      defaultCloudBaseUrl: 'https://erp.neuradix.com',
      themePrimary: '#2B6F77',
      themeSecondary: '#86A96F',
      themeAccent: '#5E6B73',
      themeTextOnPrimary: '#FFFFFF',
      themeSurface: '#F4F7F5',
      themeActive: '#355B66',
    );

    final repaired = repairHostedCloudConfig(original);

    expect(repaired.baseUrl, original.baseUrl);
    expect(repaired.defaultCloudBaseUrl, original.defaultCloudBaseUrl);
    expect(repaired.useSsl, isTrue);
  });

  test('does not rewrite dedicated backend configs', () {
    final original = const BootstrapConfig(
      baseUrl: 'http://neuradix-cassar.localhost:8008',
      useSsl: false,
      deploymentMode: 'external_backend',
      planType: 'free_local',
      brandName: 'CassarCamilleri POS',
      supportEmail: 'support@neuradix.local',
      defaultCloudBaseUrl: 'http://neuradix-cloud.localhost:8018',
      themePrimary: '#2B6F77',
      themeSecondary: '#86A96F',
      themeAccent: '#5E6B73',
      themeTextOnPrimary: '#FFFFFF',
      themeSurface: '#F4F7F5',
      themeActive: '#355B66',
    );

    final repaired = repairHostedCloudConfig(original);

    expect(repaired.baseUrl, original.baseUrl);
    expect(repaired.defaultCloudBaseUrl, original.defaultCloudBaseUrl);
    expect(repaired.deploymentMode, 'external_backend');
  });

  testWidgets('renders the tablet left rail entries', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NeuradixTheme.light(),
        home: const Scaffold(body: NeuradixLeftRailPreview()),
      ),
    );
    await tester.pump();

    expect(find.text('Order'), findsWidgets);
    expect(find.text('Customer'), findsWidgets);
    expect(find.text('Plan & Sync'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('My Profile'), findsWidgets);
  });

  testWidgets('renders the left rail cleanly in a tablet-width column', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NeuradixTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 132,
            height: 900,
            child: NeuradixLeftRailPreview(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final orderSize = tester.getSize(
      find.ancestor(
        of: find.text('Order'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final customerSize = tester.getSize(
      find.ancestor(
        of: find.text('Customer'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final planSyncSize = tester.getSize(
      find.ancestor(
        of: find.text('Plan & Sync'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final historySize = tester.getSize(
      find.ancestor(
        of: find.text('History'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final profileSize = tester.getSize(
      find.ancestor(
        of: find.text('My Profile'),
        matching: find.byType(AnimatedContainer),
      ),
    );

    expect(find.text('Plan & Sync'), findsOneWidget);
    expect(find.text('My Profile'), findsOneWidget);
    expect(orderSize, equals(customerSize));
    expect(orderSize, equals(planSyncSize));
    expect(orderSize, equals(historySize));
    expect(orderSize, equals(profileSize));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disables login actions while a login request is busy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NeuradixTheme.light(),
        home: const Scaffold(body: NeuradixLoginPreview(busy: true)),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Sign In'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Preview Offline'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Forgot Password'),
          )
          .onPressed,
      isNull,
    );
    final usernameField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(usernameField.enabled, isFalse);
  });

  testWidgets('prefills the seeded local UAT login credentials', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NeuradixTheme.light(),
        home: const Scaffold(body: NeuradixLoginPreview()),
      ),
    );
    await tester.pump();

    final usernameField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    final passwordField = tester.widget<TextField>(
      find.byType(TextField).at(1),
    );
    expect(usernameField.controller?.text, 'sara.camilleri@neuradix.local');
    expect(passwordField.controller?.text, 'NeuradixDemo!2026');
  });

  testWidgets('removes shell metadata pills from the live POS header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NeuradixTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: const NeuradixShellHeaderPreview(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('CassarCamilleri POS'), findsOneWidget);
    expect(find.text('Instance: http://127.0.0.1:8008'), findsNothing);
    expect(find.text('Mode: Live'), findsNothing);
    expect(find.text('Queued: 0'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text && (widget.data?.startsWith('Plan Date: ') ?? false),
      ),
      findsNothing,
    );
    expect(find.text('Support: support@neuradix.local'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('keeps the medium-tablet order view in side-by-side mode', () {
    expect(posOrderUsesCompactLayout(1039), isTrue);
    expect(posOrderUsesCompactLayout(1040), isFalse);
    expect(posOrderCartPanelWidth(1039), double.infinity);
    expect(posOrderCartPanelWidth(1100), 340);
    expect(posOrderCartPanelWidth(1280), 405);
  });

  test('keeps the hosted sales cart visible on medium tablets', () {
    expect(hostedSalesUsesCompactLayout(919), isTrue);
    expect(hostedSalesUsesCompactLayout(920), isFalse);
    expect(hostedSalesCartPanelWidth(919), double.infinity);
    expect(hostedSalesCartPanelWidth(1100), 360);
    expect(hostedSalesCartPanelWidth(1280), 420);
  });
}
