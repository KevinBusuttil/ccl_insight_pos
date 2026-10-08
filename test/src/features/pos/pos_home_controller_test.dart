import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/pos_cache_repository.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/orders/local_order_repository.dart';
import 'package:neuradix_pos/src/features/orders/order_models.dart';
import 'package:neuradix_pos/src/features/pos/pos_home_controller.dart';
import 'package:neuradix_pos/src/features/pos/pos_models.dart';
import 'package:neuradix_pos/src/features/pos/neuradix_api_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Harness {
  _Harness({
    required this.database,
    required this.openedDatabase,
    required this.cacheRepository,
    required this.orderRepository,
  });

  final NeuradixDatabase database;
  final Database openedDatabase;
  final PosCacheRepository cacheRepository;
  final LocalOrderRepository orderRepository;
}

class FakeNeuradixApiClient extends NeuradixApiClient {
  FakeNeuradixApiClient({
    required this.customers,
    required List<PosCatalogGroup> defaultCatalog,
    Map<String, List<PosCatalogGroup>>? catalogByCustomer,
    Map<String, List<PosVisitPlanEntry>>? weekPlanByStart,
    Map<String, PosOfflineDaySyncPack>? daySyncPackByDate,
    required List<PosHistoryOrder> history,
    required PosAccountSummary account,
    required List<Map<String, dynamic>> taxes,
    required Map<String, PosCustomerPolicy> policies,
    required Map<String, PosIssueStatement> issueStatements,
    Map<String, PosCustomer>? customersByMobile,
    this.failSubmissions = false,
    this.failCustomerContextRequests = false,
  }) : _defaultCatalog = defaultCatalog,
       _catalogByCustomer =
           catalogByCustomer ?? const <String, List<PosCatalogGroup>>{},
       _weekPlanByStart =
           weekPlanByStart ?? const <String, List<PosVisitPlanEntry>>{},
       _daySyncPackByDate =
           daySyncPackByDate ?? const <String, PosOfflineDaySyncPack>{},
       _history = history,
       _account = account,
       _taxes = taxes,
       _policies = policies,
       _issueStatements = issueStatements,
       _customersByMobile = customersByMobile ?? const <String, PosCustomer>{},
       super(baseUrl: 'http://neuradix-cassar.localhost:8008');

  final List<PosCustomer> customers;
  final List<PosCatalogGroup> _defaultCatalog;
  final Map<String, List<PosCatalogGroup>> _catalogByCustomer;
  final Map<String, List<PosVisitPlanEntry>> _weekPlanByStart;
  final Map<String, PosOfflineDaySyncPack> _daySyncPackByDate;
  final List<PosHistoryOrder> _history;
  final PosAccountSummary _account;
  final List<Map<String, dynamic>> _taxes;
  final Map<String, PosCustomerPolicy> _policies;
  final Map<String, PosIssueStatement> _issueStatements;
  final Map<String, PosCustomer> _customersByMobile;
  final List<String?> catalogRequests = <String?>[];
  final List<Map<String, Object?>> submittedPayloads = <Map<String, Object?>>[];
  bool failSubmissions;
  bool failCustomerContextRequests;

  bool failQuotes = false;
  final List<Map<String, Object?>> quoteRequests = [];
  @override
  Future<Map<String, dynamic>> quoteCart(Map<String, Object?> cart) async {
    quoteRequests.add(cart);
    if (failQuotes) throw const NeuradixApiException('pricing unavailable');
    final rows = (cart['items'] as List).cast<Map>();
    final items =
        rows
            .map(
              (row) => <String, Object?>{
                ...Map<String, Object?>.from(row),
                'rate':
                    cart['customer'] == 'CUST-002'
                        ? 4.0
                        : ((row['qty'] as num) >= 2 ? 5.0 : 10.0),
              },
            )
            .toList();
    final net = items.fold<double>(
      0,
      (sum, row) =>
          sum +
          (row['rate'] as num).toDouble() * (row['qty'] as num).toDouble(),
    );
    return {
      'items': items,
      'net_total': net,
      'tax_total': net * 0.18,
      'grand_total': net * 1.18,
      'quote_token': 'test-token',
    };
  }

  @override
  Future<List<PosCustomer>> getCustomers({
    required String hubManager,
    String searchText = '',
  }) async {
    return customers;
  }

  @override
  Future<List<PosCatalogGroup>> getCatalog({String? customer}) async {
    if (failCustomerContextRequests && customer != null) {
      throw const NeuradixApiException('offline');
    }
    catalogRequests.add(customer);
    return _catalogByCustomer[customer] ?? _defaultCatalog;
  }

  @override
  Future<List<PosHistoryOrder>> getHistory({
    required String hubManager,
    String? customer,
  }) async {
    return _history;
  }

  @override
  Future<PosAccountSummary> getAccount({required String hubManager}) async {
    return _account;
  }

  @override
  Future<List<Map<String, dynamic>>> getTaxes() async {
    return _taxes;
  }

  @override
  Future<PosCustomerPolicy> getCustomerPolicy(String customer) async {
    if (failCustomerContextRequests) {
      throw const NeuradixApiException('offline');
    }
    return _policies[customer]!;
  }

  @override
  Future<PosIssueStatement> getIssueStatement(String customer) async {
    if (failCustomerContextRequests) {
      throw const NeuradixApiException('offline');
    }
    return _issueStatements[customer]!;
  }

  @override
  Future<PosCustomer?> getCustomerByMobile(String mobileNo) async {
    return _customersByMobile[mobileNo];
  }

  @override
  Future<List<PosVisitPlanEntry>> getWeekPlan({
    required String weekStart,
    String? salesRep,
  }) async {
    return _weekPlanByStart[weekStart] ?? const <PosVisitPlanEntry>[];
  }

  @override
  Future<PosOfflineDaySyncPack> getDaySyncPack({
    required String syncDate,
    String? salesRep,
    bool includeCustomerDirectory = true,
    String? customerModifiedSince,
    String? catalogModifiedSince,
  }) async {
    return _daySyncPackByDate[syncDate] ??
        PosOfflineDaySyncPack(
          salesRep: salesRep ?? 'sara.camilleri',
          syncDate: syncDate,
          weekStart: '2026-06-08',
          syncCustomerLimit: 10,
          planEntries: const <PosVisitPlanEntry>[],
          customerDirectory: customers,
          catalogGroups: _defaultCatalog,
          customerPriceRows: const <PosCustomerPriceSnapshot>[],
          customerPolicies: const <PosCustomerPolicy>[],
          imageManifest: const <PosImageManifestEntry>[],
          syncCursors: const <String, String>{},
        );
  }

  @override
  Future<String> submitSalesOrder(Map<String, Object?> payload) async {
    submittedPayloads.add(payload);
    if (failSubmissions) {
      throw const NeuradixApiException('Backend request failed.');
    }
    return 'SO-TEST-${submittedPayloads.length.toString().padLeft(4, '0')}';
  }
}

Future<_Harness> _openHarness() async {
  sqfliteFfiInit();
  final database = NeuradixDatabase(
    databaseFactoryOverride: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final openedDatabase = await database.open();
  return _Harness(
    database: database,
    openedDatabase: openedDatabase,
    cacheRepository: PosCacheRepository(openedDatabase),
    orderRepository: LocalOrderRepository(openedDatabase),
  );
}

PosIssueStatement _issueStatement(
  String customerId, {
  bool minimumOrderRequired = false,
}) {
  return PosIssueStatement(
    customerId: customerId,
    balance: 842.05,
    paymentTerm: 'N30D',
    vat: 'MT23227102',
    primaryAddress: 'Mdina, Malta',
    minimumOrderRequired: minimumOrderRequired,
    rows: const <PosIssueStatementRow>[
      PosIssueStatementRow(
        invoiceId: 'SIN-0001',
        invoiceDate: '2026-06-04',
        dueDate: '2026-07-04',
        amount: 497.25,
        balance: 497.25,
        totalRowBalance: 497.25,
        currency: 'EUR',
        transactionType: 'Sales',
      ),
      PosIssueStatementRow(
        invoiceId: 'SIN-0002',
        invoiceDate: '2026-06-07',
        dueDate: '2026-06-28',
        amount: 344.80,
        balance: 842.05,
        totalRowBalance: 344.80,
        currency: 'EUR',
        transactionType: 'Sales',
      ),
    ],
  );
}

LocalOrder _queuedOrder({
  required String clientOrderId,
  required String customerId,
}) {
  final payload = <String, Object?>{
    'client_order_id': clientOrderId,
    'customer': customerId,
    'hub_manager': 'sara.camilleri',
    'transaction_date': '2026-06-10',
    'delivery_date': '2026-06-10',
    'items': <Map<String, Object?>>[
      <String, Object?>{
        'item_code': 'COFFEE-001',
        'item_name': 'Classic Blend Beans',
        'group_name': 'Coffee',
        'qty': 2,
        'rate': 11.5,
        'notes': 'Queued retry note',
      },
    ],
  };
  return LocalOrder(
    clientOrderId: clientOrderId,
    customerId: customerId,
    totalAmount: 23,
    payloadJson: jsonEncode(payload),
    status: 'queued',
    updatedAtIso: '2026-06-10T10:00:00Z',
  );
}

PosVisitPlanEntry _planEntry({
  required String id,
  required String customerId,
  required String customerName,
  required String customerCode,
  required String visitDate,
  required int sequenceNo,
}) {
  return PosVisitPlanEntry(
    id: id,
    salesRep: 'sara.camilleri',
    customerId: customerId,
    customerName: customerName,
    customerCode: customerCode,
    visitDate: visitDate,
    sequenceNo: sequenceNo,
    status: 'Planned',
    notes: '',
    startsOn: '$visitDate 08:00:00',
    endsOn: '$visitDate 10:00:00',
    modified: '$visitDate 07:00:00',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'launchFlow replays queued orders and refreshes cached snapshots',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());

      await harness.cacheRepository.replaceCustomers(
        PosPreviewData.customers.take(1).toList(),
      );
      await harness.cacheRepository.replaceCatalog(
        PosPreviewData.catalog.take(1).toList(),
      );
      await harness.cacheRepository.saveHistorySnapshot(
        const <PosHistoryOrder>[],
      );
      await harness.cacheRepository.saveAccountSnapshot(PosPreviewData.account);
      await harness.cacheRepository.saveTaxSnapshot(
        const <Map<String, dynamic>>[],
      );
      await harness.orderRepository.enqueueSubmit(
        _queuedOrder(clientOrderId: 'QUEUE-001', customerId: 'CUST-001'),
      );

      final apiClient = FakeNeuradixApiClient(
        customers: PosPreviewData.customers,
        defaultCatalog: PosPreviewData.catalog,
        history: PosPreviewData.history,
        account: PosPreviewData.account,
        taxes: const <Map<String, dynamic>>[
          <String, dynamic>{'rate': 18, 'description': 'VAT 18%'},
        ],
        policies: PosPreviewData.policyByCustomer,
        issueStatements: <String, PosIssueStatement>{
          'CUST-001': _issueStatement('CUST-001'),
        },
      );

      final controller = PosHomeController(
        instanceUrl: 'http://neuradix-cassar.localhost:8008',
        bootstrap: PosPreviewData.bootstrap,
        session: const PosLoginSession(
          username: 'sara.camilleri',
          email: 'sara.camilleri@neuradix.local',
          apiKey: 'key',
          apiSecret: 'secret',
          hubManager: 'sara.camilleri',
        ),
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        apiClient: apiClient,
      );

      await controller.hydrate();
      expect(controller.pendingQueue, hasLength(1));

      await controller.launchFlow();

      expect(apiClient.submittedPayloads, hasLength(1));
      expect(controller.pendingQueue, isEmpty);
      expect(controller.customers, hasLength(PosPreviewData.customers.length));
      expect(
        controller.catalogGroups,
        hasLength(PosPreviewData.catalog.length),
      );
      expect(controller.history, isNotEmpty);
      expect(controller.account?.currencySymbol, 'EUR');
      expect(controller.statusMessage, 'Local cache synced with the bench.');
      expect(controller.isOffline, isFalse);
    },
  );

  test(
    'selectCustomer reloads customer-priced catalog and issue statement data',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());

      await harness.cacheRepository.replaceCatalog(PosPreviewData.catalog);

      final customer = PosPreviewData.customers.first;
      final repricedCatalog = <PosCatalogGroup>[
        PosCatalogGroup(
          groupName: 'Coffee',
          items: <PosCatalogItem>[
            PosCatalogItem(
              itemCode: 'COFFEE-001',
              groupName: 'Coffee',
              displayName: 'Classic Blend Beans',
              imageUrl: '',
              price: 7.25,
              stockQty: 18,
              taxRows: const <Map<String, dynamic>>[],
              comboItems: const <Map<String, dynamic>>[],
              attributeGroups: const <Map<String, dynamic>>[],
            ),
          ],
        ),
      ];
      final apiClient = FakeNeuradixApiClient(
        customers: PosPreviewData.customers,
        defaultCatalog: PosPreviewData.catalog,
        catalogByCustomer: <String, List<PosCatalogGroup>>{
          customer.customerCode: repricedCatalog,
        },
        history: PosPreviewData.history,
        account: PosPreviewData.account,
        taxes: const <Map<String, dynamic>>[],
        policies: <String, PosCustomerPolicy>{
          customer.id: const PosCustomerPolicy(
            customer: 'CUST-001',
            customerCode: 'AX-1001',
            isFrozen: false,
            minimumOrderAmount: 50,
            minimumOrderRequired: false,
            notesBypassMinimum: true,
            outstandingAmount: 842.05,
            hasOutstandingDocuments: true,
            sameDayOrders: 1,
          ),
        },
        issueStatements: <String, PosIssueStatement>{
          customer.id: _issueStatement(
            customer.id,
            minimumOrderRequired: false,
          ),
        },
      );
      final controller = PosHomeController(
        instanceUrl: 'http://neuradix-cassar.localhost:8008',
        bootstrap: PosPreviewData.bootstrap,
        session: const PosLoginSession(
          username: 'sara.camilleri',
          email: 'sara.camilleri@neuradix.local',
          apiKey: 'key',
          apiSecret: 'secret',
          hubManager: 'sara.camilleri',
        ),
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        apiClient: apiClient,
        initialCustomers: PosPreviewData.customers,
        initialCatalog: PosPreviewData.catalog,
      );

      final loadingStates = <bool>[];
      controller.addListener(
        () => loadingStates.add(controller.isCustomerLoading),
      );
      final selection = controller.selectCustomer(customer);
      expect(controller.isCustomerLoading, isTrue);
      expect(controller.isBusy, isTrue);
      await selection;
      expect(controller.isCustomerLoading, isFalse);
      expect(loadingStates, containsAllInOrder([true, false]));
      final categories = controller.allCategories.take(2).toSet();
      controller.setCategories(categories);
      expect(controller.selectedCategories, categories);
      expect(
        controller.catalogGroups.every(
          (group) => categories.contains(group.groupName),
        ),
        isTrue,
      );
      controller.setCategories({});
      expect(controller.selectedCategories, isEmpty);

      expect(apiClient.catalogRequests, <String?>['AX-1001']);
      expect(controller.selectedCustomer?.id, customer.id);
      expect(controller.selectedPolicy?.minimumOrderRequired, isFalse);
      expect(controller.selectedIssueStatement?.rows, hasLength(2));
      expect(controller.catalogGroups.single.items.single.price, 7.25);
    },
  );

  test(
    'submitCurrentOrder allows below-minimum orders only when every line has notes',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());

      final controller = PosHomeController(
        instanceUrl: 'http://neuradix-cassar.localhost:8008',
        bootstrap: PosPreviewData.bootstrap,
        session: PosPreviewData.session,
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        initialCustomers: PosPreviewData.customers,
        initialCatalog: PosPreviewData.catalog,
        initialPolicies: const <String, PosCustomerPolicy>{
          'CUST-001': PosCustomerPolicy(
            customer: 'CUST-001',
            customerCode: 'AX-1001',
            isFrozen: false,
            minimumOrderAmount: 50,
            minimumOrderRequired: true,
            notesBypassMinimum: true,
            outstandingAmount: 0,
            hasOutstandingDocuments: false,
            sameDayOrders: 0,
          ),
        },
      );

      await controller.selectCustomer(PosPreviewData.customers.first);
      controller.addItem(PosPreviewData.catalog.first.items.first);
      controller.addItem(PosPreviewData.catalog[1].items.first);

      await controller.submitCurrentOrder();

      expect(controller.statusMessage, contains('Minimum order is 50.00 EUR.'));
      expect(await harness.orderRepository.queuedOrderCount(), 0);

      controller.setLineNotes(
        controller.cartLines[0],
        'Customer requested early delivery',
      );
      controller.setLineNotes(controller.cartLines[1], 'Split case accepted');

      await controller.submitCurrentOrder();

      expect(await harness.orderRepository.queuedOrderCount(), 1);
      expect(
        controller.statusMessage,
        contains('Preview mode queued the order locally.'),
      );
    },
  );

  test(
    'addItem appends a cart line, increments qty, and reports status',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());

      final controller = PosHomeController(
        instanceUrl: 'http://neuradix-cassar.localhost:8008',
        bootstrap: PosPreviewData.bootstrap,
        session: PosPreviewData.session,
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        initialCatalog: PosPreviewData.catalog,
      );

      final item = PosPreviewData.catalog.first.items.first;

      controller.addItem(item);

      expect(controller.cartLines, hasLength(1));
      expect(controller.cartLines.single.itemCode, item.itemCode);
      expect(controller.cartLines.single.qty, 1);
      expect(
        controller.statusMessage,
        '${item.displayName} added to the cart.',
      );

      controller.addItem(item);

      expect(controller.cartLines, hasLength(1));
      expect(controller.cartLines.single.qty, 2);
    },
  );

  test(
    'prepareLogout blocks logout when queued orders still need backend replay',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());

      await harness.orderRepository.enqueueSubmit(
        _queuedOrder(clientOrderId: 'QUEUE-002', customerId: 'CUST-001'),
      );

      final controller = PosHomeController(
        instanceUrl: 'http://neuradix-cassar.localhost:8008',
        bootstrap: PosPreviewData.bootstrap,
        session: const PosLoginSession(
          username: 'sara.camilleri',
          email: 'sara.camilleri@neuradix.local',
          apiKey: 'key',
          apiSecret: 'secret',
          hubManager: 'sara.camilleri',
        ),
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        apiClient: FakeNeuradixApiClient(
          customers: PosPreviewData.customers,
          defaultCatalog: PosPreviewData.catalog,
          history: PosPreviewData.history,
          account: PosPreviewData.account,
          taxes: const <Map<String, dynamic>>[],
          policies: PosPreviewData.policyByCustomer,
          issueStatements: <String, PosIssueStatement>{
            'CUST-001': _issueStatement('CUST-001'),
          },
          failSubmissions: true,
        ),
      );

      final allowed = await controller.prepareLogout();

      expect(allowed, isFalse);
      expect(
        controller.statusMessage,
        contains('Queued orders still need the backend.'),
      );
      expect(await harness.orderRepository.queuedOrderCount(), 1);
    },
  );

  test(
    'syncSelectedDayData caches plan rows and offline price overlays',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());

      final syncDate = DateTime.now().toIso8601String().split('T').first;
      final dayPack = PosOfflineDaySyncPack(
        salesRep: 'sara.camilleri',
        syncDate: syncDate,
        weekStart: syncDate,
        syncCustomerLimit: 10,
        planEntries: <PosVisitPlanEntry>[
          _planEntry(
            id: 'PLAN-001',
            customerId: 'CUST-001',
            customerName: 'Cassar Retail Valletta',
            customerCode: 'AX-1001',
            visitDate: syncDate,
            sequenceNo: 1,
          ),
        ],
        customerDirectory: PosPreviewData.customers,
        catalogGroups: PosPreviewData.catalog,
        customerPriceRows: <PosCustomerPriceSnapshot>[
          PosCustomerPriceSnapshot(
            syncDate: syncDate,
            customerId: 'CUST-001',
            customerCode: 'AX-1001',
            itemCode: 'COFFEE-001',
            price: 8.45,
          ),
        ],
        customerPolicies: const <PosCustomerPolicy>[
          PosCustomerPolicy(
            customer: 'CUST-001',
            customerCode: 'AX-1001',
            isFrozen: false,
            minimumOrderAmount: 50,
            minimumOrderRequired: true,
            notesBypassMinimum: true,
            outstandingAmount: 0,
            hasOutstandingDocuments: false,
            sameDayOrders: 0,
          ),
        ],
        imageManifest: const <PosImageManifestEntry>[
          PosImageManifestEntry(
            itemCode: 'COFFEE-001',
            imageUrl: '/files/coffee.png',
            imageVersion: '2026-06-10 10:00:00',
          ),
        ],
        syncCursors: const <String, String>{
          'customer_modified_through': '2026-06-10 10:05:00',
          'catalog_modified_through': '2026-06-10 10:00:00',
        },
      );

      final controller = PosHomeController(
        instanceUrl: 'http://neuradix-cassar.localhost:8008',
        bootstrap: PosPreviewData.bootstrap,
        session: const PosLoginSession(
          username: 'sara.camilleri',
          email: 'sara.camilleri@neuradix.local',
          apiKey: 'key',
          apiSecret: 'secret',
          hubManager: 'sara.camilleri',
        ),
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        apiClient: FakeNeuradixApiClient(
          customers: PosPreviewData.customers,
          defaultCatalog: PosPreviewData.catalog,
          daySyncPackByDate: <String, PosOfflineDaySyncPack>{syncDate: dayPack},
          history: PosPreviewData.history,
          account: PosPreviewData.account,
          taxes: const <Map<String, dynamic>>[],
          policies: PosPreviewData.policyByCustomer,
          issueStatements: <String, PosIssueStatement>{
            'CUST-001': _issueStatement('CUST-001'),
          },
        ),
        initialCustomers: PosPreviewData.customers,
        initialCatalog: PosPreviewData.catalog,
      );

      await controller.hydrate();
      await controller.selectPlanDate(syncDate);
      await controller.syncSelectedDayData();

      final repricedCatalog = await harness.cacheRepository.readCatalog(
        syncDate: syncDate,
        customerId: 'CUST-001',
      );
      final cachedPlan = await harness.cacheRepository
          .readVisitPlanEntriesForWeek(
            controller.currentWeekDates.first,
            'sara.camilleri',
          );

      expect(cachedPlan, hasLength(1));
      expect(cachedPlan.single.customerId, 'CUST-001');
      expect(repricedCatalog.first.items.first.price, 8.45);
      expect(
        await harness.cacheRepository.hasCustomerPriceSync(
          syncDate,
          'CUST-001',
        ),
        isTrue,
      );
    },
  );

  test(
    'offline customer selection blocks unsynced customers from pricing view',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());

      final controller = PosHomeController(
        instanceUrl: 'http://neuradix-cassar.localhost:8008',
        bootstrap: PosPreviewData.bootstrap,
        session: const PosLoginSession(
          username: 'sara.camilleri',
          email: 'sara.camilleri@neuradix.local',
          apiKey: 'key',
          apiSecret: 'secret',
          hubManager: 'sara.camilleri',
        ),
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        apiClient: FakeNeuradixApiClient(
          customers: PosPreviewData.customers,
          defaultCatalog: PosPreviewData.catalog,
          history: PosPreviewData.history,
          account: PosPreviewData.account,
          taxes: const <Map<String, dynamic>>[],
          policies: const <String, PosCustomerPolicy>{},
          issueStatements: const <String, PosIssueStatement>{},
          failCustomerContextRequests: true,
        ),
        initialCustomers: PosPreviewData.customers,
        initialCatalog: PosPreviewData.catalog,
      );

      await controller.hydrate();
      await controller.selectCustomer(PosPreviewData.customers.first);

      expect(controller.isOffline, isTrue);
      expect(controller.catalogGroups, isEmpty);
      expect(controller.statusMessage, contains('Plan & Sync'));
    },
  );
  test(
    'dedicated pricing re-quotes quantity and customer; failed quotes preserve cart',
    () async {
      final harness = await _openHarness();
      addTearDown(() async => harness.database.close());
      final api = FakeNeuradixApiClient(
        customers: PosPreviewData.customers,
        defaultCatalog: PosPreviewData.catalog,
        history: [],
        account: PosPreviewData.account,
        taxes: [],
        policies: PosPreviewData.policyByCustomer,
        issueStatements: {
          'CUST-001': _issueStatement('CUST-001'),
          'CUST-002': _issueStatement('CUST-002'),
        },
      );
      final controller = PosHomeController(
        instanceUrl: 'http://uat',
        bootstrap: PosBootstrapBundle.fromPlatform({
          'features': {'server_cart_quotes': true},
          'minimum_order_amount': 0,
        }),
        session: const PosLoginSession(
          username: 'rep',
          email: 'rep@example.com',
          apiKey: 'k',
          apiSecret: 's',
          hubManager: 'rep',
        ),
        cacheRepository: harness.cacheRepository,
        orderRepository: harness.orderRepository,
        apiClient: api,
      );
      final item = PosPreviewData.catalog.first.items.first;
      await controller.addItem(item);
      expect(controller.cartLines, isEmpty);
      await controller.selectCustomer(PosPreviewData.customers.first);
      await controller.addItem(item);
      expect(controller.cartLines.single.price, 10);
      await controller.changeLineQuantity(controller.cartLines.single, 1);
      expect(controller.cartLines.single.price, 5);
      expect(controller.grandTotal, closeTo(11.8, 0.001));
      await controller.selectCustomer(PosPreviewData.customers[1]);
      expect(controller.cartLines.single.price, 4);
      expect(api.quoteRequests.last['customer'], 'CUST-002');
      api.failQuotes = true;
      await controller.submitCurrentOrder();
      expect(api.submittedPayloads, isEmpty);
      expect(controller.cartLines, hasLength(1));
      expect(await harness.orderRepository.readPendingQueue(), isEmpty);
      expect(controller.statusMessage, contains('Prices unavailable'));
      await controller.changeLineQuantity(controller.cartLines.single, -2);
      expect(controller.cartLines, isEmpty);
    },
  );
}
