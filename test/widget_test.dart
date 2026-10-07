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

  testWidgets('phone shell header preserves space for the order view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosShellHeader(
            brandName: 'Neuradix CassarCamilleri',
            onRefresh: () async {},
            onEditInstance: () async {},
            onLogout: () async {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PosShellHeader)).height, lessThan(100));
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byTooltip('Logout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact cart stays reachable and opens without catalog scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(430, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactOrderWorkspace(
              catalog: Column(
                children: [Text('Products'), Expanded(child: SizedBox())],
              ),
              cart: Text('Selected cart item'),
              cartLabel: 'View cart (1) · 2.00',
            ),
          ),
        ),
      );
      final button = find.text('View cart (1) · 2.00');
      expect(tester.getRect(button).bottom, lessThan(800));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Selected cart item'), findsOneWidget);
      await tester.tap(find.byTooltip('Close cart'));
      await tester.pumpAndSettle();
      expect(find.text('Selected cart item'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pricing and sync progress is visible with an accessible label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PosLoadingIndicator(
            label: 'Loading customer prices and account…',
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Loading customer prices and account…'), findsOneWidget);
  });

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

  test('hosted shell state is scoped by business and shop', () {
    const mainShop = BootstrapConfig(
      baseUrl: 'https://erp.neuradix.com',
      useSsl: true,
      deploymentMode: 'neuradix_cloud',
      planType: 'free_local',
      brandName: 'Neuradix POS',
      supportEmail: 'support@neuradix.local',
      defaultCloudBaseUrl: 'https://erp.neuradix.com',
      themePrimary: '#2B6F77',
      themeSecondary: '#86A96F',
      themeAccent: '#5E6B73',
      themeTextOnPrimary: '#FFFFFF',
      themeSurface: '#F4F7F5',
      themeActive: '#355B66',
      businessId: 'NBIZ-1',
      shopId: 'SHOP-MAIN',
    );
    final branchShop = mainShop.copyWith(shopId: 'SHOP-BRANCH');
    final otherBusiness = mainShop.copyWith(businessId: 'NBIZ-2');

    expect(hostedShellStateScope(mainShop), 'NBIZ-1:SHOP-MAIN');
    expect(
      hostedShellStateScope(branchShop),
      isNot(hostedShellStateScope(mainShop)),
    );
    expect(
      hostedShellStateScope(otherBusiness),
      isNot(hostedShellStateScope(mainShop)),
    );
    expect(
      hostedShellStateScope(mainShop.copyWith(shopName: 'Renamed Main Shop')),
      hostedShellStateScope(mainShop),
    );
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

  testWidgets('offers metadata-only local multi-shop registration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NeuradixTheme.light(),
        home: const Scaffold(body: NeuradixHostedAuthPreview()),
      ),
    );
    await tester.pump();

    expect(find.text('Local Multi-Shop'), findsOneWidget);
    await tester.tap(find.text('Local Multi-Shop'));
    await tester.pump();

    expect(
      find.textContaining(
        'Customers and finalized sales stay on trusted devices',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('permanent cloud payload storage'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('local-sync-first-shop-name')), findsOneWidget);
    expect(find.byKey(const Key('local-sync-first-shop-code')), findsOneWidget);
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
    expect(posOrderUsesCompactLayout(1280, maxHeight: 500), isTrue);
    expect(posOrderUsesCompactLayout(1280, maxHeight: 800), isFalse);
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

  test(
    'scrolls noncompact sales panes when the keyboard compresses height',
    () {
      expect(
        hostedSalesUsesScrollableNonCompactPane(maxWidth: 1200, maxHeight: 619),
        isTrue,
      );
      expect(
        hostedSalesUsesScrollableNonCompactPane(maxWidth: 1200, maxHeight: 620),
        isFalse,
      );
      expect(
        hostedSalesUsesScrollableNonCompactPane(maxWidth: 700, maxHeight: 400),
        isFalse,
      );
    },
  );

  test('keeps compact hosted content scrollable on short phone screens', () {
    expect(hostedCompactBodyHeight(420), 520);
    expect(hostedCompactBodyHeight(640), 520);
    expect(hostedCompactBodyHeight(1280), 920);
    expect(hostedCompactBodyHeight(1800), 1000);
  });
}
