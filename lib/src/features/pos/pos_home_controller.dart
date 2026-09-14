import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/local/pos_cache_repository.dart';
import '../orders/local_order_repository.dart';
import '../orders/order_models.dart';
import 'catalog_image_sync_service.dart';
import 'pos_debug_log.dart';
import 'pos_models.dart';
import 'neuradix_api_client.dart';

class PosHomeController extends ChangeNotifier {
  PosHomeController({
    required this.instanceUrl,
    required this.bootstrap,
    required this.session,
    required this.cacheRepository,
    required this.orderRepository,
    this.apiClient,
    CatalogImageSyncService? imageSyncService,
    List<PosCustomer> initialCustomers = const <PosCustomer>[],
    List<PosCatalogGroup> initialCatalog = const <PosCatalogGroup>[],
    List<PosHistoryOrder> initialHistory = const <PosHistoryOrder>[],
    PosAccountSummary? initialAccount,
    List<Map<String, dynamic>> initialTaxes = const <Map<String, dynamic>>[],
    Map<String, PosCustomerPolicy> initialPolicies =
        const <String, PosCustomerPolicy>{},
    Map<String, PosIssueStatement> initialIssueStatements =
        const <String, PosIssueStatement>{},
  }) : _allCustomers = List<PosCustomer>.from(initialCustomers),
       _visibleCustomers = List<PosCustomer>.from(initialCustomers),
       _baseCatalogGroups = List<PosCatalogGroup>.from(initialCatalog),
       _activeCatalogSourceGroups = List<PosCatalogGroup>.from(initialCatalog),
       _catalogGroups = List<PosCatalogGroup>.from(initialCatalog),
       _history = List<PosHistoryOrder>.from(initialHistory),
       _account = initialAccount,
       _taxRows = List<Map<String, dynamic>>.from(initialTaxes),
       _policyByCustomer = Map<String, PosCustomerPolicy>.from(initialPolicies),
       _issueStatements = Map<String, PosIssueStatement>.from(
         initialIssueStatements,
       ),
       _imageSyncService = imageSyncService ?? createCatalogImageSyncService() {
    _allCategories = _extractCategoryNames(_baseCatalogGroups);
    _selectedPlanDate = _dateOnly();
  }

  final String instanceUrl;
  final PosBootstrapBundle bootstrap;
  final PosLoginSession session;
  final PosCacheRepository cacheRepository;
  final LocalOrderRepository orderRepository;
  final NeuradixApiClient? apiClient;
  final CatalogImageSyncService _imageSyncService;

  final List<CartLine> _cartLines = <CartLine>[];
  final Map<String, PosCustomerPolicy> _policyByCustomer;
  final Map<String, PosIssueStatement> _issueStatements;

  List<PosCustomer> _allCustomers;
  List<PosCustomer> _visibleCustomers;
  List<PosCatalogGroup> _baseCatalogGroups;
  List<PosCatalogGroup> _activeCatalogSourceGroups;
  List<PosCatalogGroup> _catalogGroups;
  List<PosHistoryOrder> _history;
  List<Map<String, dynamic>> _taxRows;
  PosAccountSummary? _account;
  List<String> _allCategories = <String>[];
  List<LocalOrder> _parkedOrders = <LocalOrder>[];
  List<SyncQueueEntry> _pendingQueue = <SyncQueueEntry>[];
  List<PosVisitPlanEntry> _weekPlanEntries = <PosVisitPlanEntry>[];
  PosCustomer? _selectedCustomer;
  PosCustomerPolicy? _selectedPolicy;
  PosIssueStatement? _selectedIssueStatement;
  String? _selectedCategory;
  String _selectedView = 'Order';
  String _customerSearch = '';
  String _catalogSearch = '';
  String _orderNotes = '';
  String _selectedPlanDate = '';
  String? _lastDaySyncAt;
  String? _statusMessage;
  bool _busy = false;
  bool _offline = false;
  bool _selectedCustomerOfflineReady = false;
  String? _loadedParkedOrderId;
  String? _loadedParkedRemoteOrderId;

  List<PosCustomer> get customers => _visibleCustomers;
  List<PosCatalogGroup> get catalogGroups => _catalogGroups;
  List<PosHistoryOrder> get history => _history;
  List<LocalOrder> get parkedOrders => _parkedOrders;
  List<SyncQueueEntry> get pendingQueue => _pendingQueue;
  List<CartLine> get cartLines => _cartLines;
  List<PosVisitPlanEntry> get weekPlanEntries => _weekPlanEntries;
  List<PosVisitPlanEntry> get plannedEntriesForSelectedDate =>
      _entriesForDate(_selectedPlanDate);
  PosCustomer? get selectedCustomer => _selectedCustomer;
  PosCustomerPolicy? get selectedPolicy => _selectedPolicy;
  PosIssueStatement? get selectedIssueStatement => _selectedIssueStatement;
  PosAccountSummary? get account => _account;
  List<String> get allCategories => _allCategories;
  String? get selectedCategory => _selectedCategory;
  String get selectedView => _selectedView;
  String get customerSearch => _customerSearch;
  String get catalogSearch => _catalogSearch;
  String get orderNotes => _orderNotes;
  String get selectedPlanDate => _selectedPlanDate;
  String? get lastDaySyncAt => _lastDaySyncAt;
  String? get statusMessage => _statusMessage;
  bool get isBusy => _busy;
  bool get isOffline => _offline;
  bool get isPreview => session.previewMode;
  bool get selectedCustomerOfflineReady => _selectedCustomerOfflineReady;

  List<String> get currentWeekDates {
    final weekStart = _weekStartForDate(_selectedPlanDate);
    return List<String>.generate(
      7,
      (int index) => _addDays(weekStart, index),
      growable: false,
    );
  }

  double get subtotal => _cartLines.fold<double>(
    0,
    (double total, CartLine line) => total + line.total,
  );

  double get taxTotal {
    return _taxRows.fold<double>(0, (double total, Map<String, dynamic> row) {
      final rate = double.tryParse('${row['rate'] ?? 0}') ?? 0;
      if (rate <= 0) {
        return total;
      }
      return total + ((subtotal * rate) / 100);
    });
  }

  double get grandTotal => subtotal + taxTotal;

  Future<void> hydrate() async {
    if (_allCustomers.isEmpty) {
      _allCustomers = await cacheRepository.searchCustomers('');
    }
    _visibleCustomers =
        _customerSearch.trim().isEmpty
            ? _allCustomers
            : await cacheRepository.searchCustomers(_customerSearch);
    if (_baseCatalogGroups.isEmpty) {
      _baseCatalogGroups = await cacheRepository.readCatalog();
    }
    _activeCatalogSourceGroups = List<PosCatalogGroup>.from(_baseCatalogGroups);
    _applyCatalogFilters();
    if (_history.isEmpty) {
      _history = await cacheRepository.readHistorySnapshot();
    }
    if (_taxRows.isEmpty) {
      _taxRows = await cacheRepository.readTaxSnapshot();
    }
    _account ??= await cacheRepository.readAccountSnapshot();
    _parkedOrders = await orderRepository.listParkedOrders();
    _pendingQueue = await orderRepository.readPendingQueue();
    _weekPlanEntries = await cacheRepository.readVisitPlanEntriesForWeek(
      _weekStartForDate(_selectedPlanDate),
      session.hubManager,
    );
    _lastDaySyncAt = await cacheRepository.readDaySyncSyncedAt(
      _selectedPlanDate,
    );
    await _mergeLocalHistory();
    PosDebugLog.info(
      'controller.hydrate',
      'customers=${PosDebugLog.summarizeCustomers(_allCustomers)} '
          'catalog_groups=${_catalogGroups.length} history=${_history.length} '
          'parked=${_parkedOrders.length} queue=${_pendingQueue.length} '
          'plan_entries=${_weekPlanEntries.length}',
    );
    notifyListeners();
  }

  Future<void> launchFlow() async {
    if (isPreview || apiClient == null) {
      return;
    }
    _busy = true;
    _statusMessage =
        'Refreshing queued orders, base catalog, visit plan, and offline caches.';
    notifyListeners();
    try {
      await syncNowFlow(showSuccessMessage: false);
      await refreshFromBackend(showMessage: false);
      await loadWeekPlan(fromBackend: true, showMessage: false);
      await orderRepository.pruneSyncedOrders(
        DateTime.now().subtract(Duration(days: bootstrap.offlineHistoryDays)),
      );
      _pendingQueue = await orderRepository.readPendingQueue();
      await _mergeLocalHistory();
      _offline = false;
      _statusMessage = 'Local cache synced with the bench.';
      PosDebugLog.info(
        'controller.launchFlow',
        'sync_complete ${PosDebugLog.summarizeCustomers(_allCustomers)} history=${_history.length} queue=${_pendingQueue.length} plan_entries=${_weekPlanEntries.length}',
      );
    } on Exception {
      _offline = true;
      _statusMessage =
          'Launch sync could not reach the bench. Showing the local cache.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void selectView(String view) {
    _selectedView = view;
    notifyListeners();
  }

  Future<void> updateCustomerSearch(String value) async {
    _customerSearch = value;
    _visibleCustomers = await cacheRepository.searchCustomers(value);
    PosDebugLog.info(
      'controller.updateCustomerSearch',
      'search="${value.trim()}" visible=${PosDebugLog.summarizeCustomers(_visibleCustomers)}',
    );
    notifyListeners();
  }

  Future<void> updateCatalogSearch(String value) async {
    _catalogSearch = value;
    _applyCatalogFilters();
    notifyListeners();
  }

  Future<void> selectCategory(String? value) async {
    _selectedCategory = value == null || value.isEmpty ? null : value;
    _applyCatalogFilters();
    notifyListeners();
  }

  Future<void> selectCustomer(PosCustomer customer) async {
    _selectedCustomer = customer;
    _selectedPolicy =
        _policyByCustomer[customer.id] ??
        PosCustomerPolicy(
          customer: customer.id,
          customerCode: customer.customerCode,
          isFrozen: customer.isFrozen,
          minimumOrderAmount: bootstrap.minimumOrderAmount,
          minimumOrderRequired: true,
          notesBypassMinimum: bootstrap.notesBypassMinimum,
          outstandingAmount: customer.outstandingAmount,
          hasOutstandingDocuments: customer.outstandingAmount > 0,
          sameDayOrders: 0,
        );
    _selectedIssueStatement = _issueStatements[customer.id];
    _selectedCustomerOfflineReady = await cacheRepository.hasCustomerPriceSync(
      _selectedPlanDate,
      customer.id,
    );
    _statusMessage = null;

    if (apiClient != null && !isPreview) {
      try {
        _busy = true;
        notifyListeners();
        final livePolicy = await apiClient!.getCustomerPolicy(customer.id);
        final liveStatement = await apiClient!.getIssueStatement(customer.id);
        final liveCatalog = await apiClient!.getCatalog(
          customer:
              customer.customerCode.isNotEmpty
                  ? customer.customerCode
                  : customer.id,
        );
        _policyByCustomer[customer.id] = livePolicy;
        _issueStatements[customer.id] = liveStatement;
        _selectedPolicy = livePolicy;
        _selectedIssueStatement = liveStatement;
        await cacheRepository.saveIssueStatement(customer.id, <String, dynamic>{
          'CustomerId': liveStatement.customerId,
          'Balance': liveStatement.balance,
          'payment_term': liveStatement.paymentTerm,
          'vat': liveStatement.vat,
          'primary_address': liveStatement.primaryAddress,
          'min_order_limit': liveStatement.minimumOrderRequired,
          'CustTrans': <String, Object?>{
            'BTLAPICustTrans': liveStatement.rows
                .map(
                  (PosIssueStatementRow row) => <String, Object?>{
                    'InvoiceId': row.invoiceId,
                    'InvoiceDate': row.invoiceDate,
                    'DueDate': row.dueDate,
                    'Amount': row.amount,
                    'Balance': row.balance,
                    'Total Row Balance': row.totalRowBalance,
                    'Currency': row.currency,
                    'TransType': row.transactionType,
                  },
                )
                .toList(growable: false),
          },
        });
        _activeCatalogSourceGroups = liveCatalog;
        _offline = false;
        _applyCatalogFilters();
      } on Exception {
        _offline = true;
        await _applyOfflineCatalogForSelectedCustomer();
      } finally {
        _busy = false;
      }
    } else {
      await _applyOfflineCatalogForSelectedCustomer();
    }

    notifyListeners();
  }

  Future<PosCustomer?> lookupCustomerByMobile(String mobileNo) async {
    final normalized = mobileNo.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final localMatch = _allCustomers.cast<PosCustomer?>().firstWhere(
      (PosCustomer? customer) => customer?.mobileNo == normalized,
      orElse: () => null,
    );
    if (localMatch != null) {
      await selectCustomer(localMatch);
      return localMatch;
    }

    if (apiClient == null || isPreview) {
      return null;
    }

    try {
      final remote = await apiClient!.getCustomerByMobile(normalized);
      if (remote == null) {
        return null;
      }
      final existingIndex = _allCustomers.indexWhere(
        (PosCustomer customer) => customer.id == remote.id,
      );
      if (existingIndex >= 0) {
        _allCustomers[existingIndex] = remote;
      } else {
        _allCustomers = <PosCustomer>[remote, ..._allCustomers];
      }
      await cacheRepository.replaceCustomers(_allCustomers);
      await updateCustomerSearch(_customerSearch);
      await selectCustomer(remote);
      return remote;
    } on Exception {
      _offline = true;
      _statusMessage =
          'Could not look up the customer on the bench. Try again when the backend is reachable.';
      notifyListeners();
      return null;
    }
  }

  Future<void> loadWeekPlan({
    String? anchorDate,
    bool fromBackend = false,
    bool showMessage = true,
  }) async {
    final resolvedAnchorDate = anchorDate ?? _selectedPlanDate;
    final weekStart = _weekStartForDate(resolvedAnchorDate);
    if (fromBackend && apiClient != null && !isPreview) {
      try {
        final entries = await apiClient!.getWeekPlan(
          weekStart: weekStart,
          salesRep: session.hubManager,
        );
        _weekPlanEntries = entries;
        await cacheRepository.replaceVisitPlanEntriesForWeek(
          weekStart,
          entries,
        );
        _offline = false;
      } on Exception {
        _offline = true;
        _weekPlanEntries = await cacheRepository.readVisitPlanEntriesForWeek(
          weekStart,
          session.hubManager,
        );
      }
    } else {
      _weekPlanEntries = await cacheRepository.readVisitPlanEntriesForWeek(
        weekStart,
        session.hubManager,
      );
    }
    _selectedPlanDate = resolvedAnchorDate;
    _lastDaySyncAt = await cacheRepository.readDaySyncSyncedAt(
      _selectedPlanDate,
    );
    if (_selectedCustomer != null) {
      _selectedCustomerOfflineReady = await cacheRepository
          .hasCustomerPriceSync(_selectedPlanDate, _selectedCustomer!.id);
      if (_offline) {
        await _applyOfflineCatalogForSelectedCustomer();
      }
    }
    if (showMessage) {
      _statusMessage = 'Loaded the visit plan week starting $weekStart.';
    }
    PosDebugLog.info(
      'controller.loadWeekPlan',
      'week_start=$weekStart entries=${_weekPlanEntries.length} selected_date=$_selectedPlanDate',
    );
    notifyListeners();
  }

  Future<void> selectPlanDate(String isoDate) async {
    _selectedPlanDate = isoDate;
    _lastDaySyncAt = await cacheRepository.readDaySyncSyncedAt(isoDate);
    if (_selectedCustomer != null) {
      _selectedCustomerOfflineReady = await cacheRepository
          .hasCustomerPriceSync(_selectedPlanDate, _selectedCustomer!.id);
      if (_offline) {
        await _applyOfflineCatalogForSelectedCustomer();
      }
    }
    notifyListeners();
  }

  Future<void> addPlanCustomer(
    PosCustomer customer, {
    String? visitDate,
  }) async {
    if (apiClient == null || isPreview || _offline) {
      _statusMessage =
          'Visit plans can only be edited while the bench is reachable.';
      notifyListeners();
      return;
    }
    final targetDate = visitDate ?? _selectedPlanDate;
    final existingDayEntries = _entriesForDate(targetDate);
    final nextSequenceNo = existingDayEntries.length + 1;
    final entries = await apiClient!.upsertVisitPlanEntries(
      salesRep: session.hubManager,
      entries: <Map<String, Object?>>[
        <String, Object?>{
          'customer': customer.id,
          'visit_date': targetDate,
          'sequence_no': nextSequenceNo,
          'status': 'Planned',
          'notes': '',
        },
      ],
    );
    await _replaceWeekPlan(entries);
    _selectedPlanDate = targetDate;
    _statusMessage = 'Added ${customer.displayName} to the visit plan.';
    notifyListeners();
  }

  Future<void> reorderPlanEntry(PosVisitPlanEntry entry, int delta) async {
    if (apiClient == null || isPreview || _offline) {
      _statusMessage =
          'Visit plans can only be edited while the bench is reachable.';
      notifyListeners();
      return;
    }
    final dayEntries = _entriesForDate(entry.visitDate);
    final currentIndex = dayEntries.indexWhere(
      (PosVisitPlanEntry row) => row.id == entry.id,
    );
    if (currentIndex < 0) {
      return;
    }
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= dayEntries.length) {
      return;
    }
    final reordered = List<PosVisitPlanEntry>.from(dayEntries);
    final moved = reordered.removeAt(currentIndex);
    reordered.insert(nextIndex, moved);
    final payload = reordered
        .asMap()
        .entries
        .map(
          (MapEntry<int, PosVisitPlanEntry> row) => <String, Object?>{
            'name': row.value.id,
            'customer': row.value.customerId,
            'visit_date': row.value.visitDate,
            'sequence_no': row.key + 1,
            'status': row.value.status,
            'notes': row.value.notes,
            'starts_on': row.value.startsOn,
            'ends_on': row.value.endsOn,
          },
        )
        .toList(growable: false);
    final entries = await apiClient!.upsertVisitPlanEntries(
      salesRep: session.hubManager,
      entries: payload,
    );
    await _replaceWeekPlan(entries);
    _statusMessage = 'Updated visit order for ${entry.visitDate}.';
    notifyListeners();
  }

  Future<void> movePlanEntry(PosVisitPlanEntry entry, String targetDate) async {
    if (apiClient == null || isPreview || _offline) {
      _statusMessage =
          'Visit plans can only be edited while the bench is reachable.';
      notifyListeners();
      return;
    }
    final targetEntries = _entriesForDate(targetDate);
    final entries = await apiClient!.upsertVisitPlanEntries(
      salesRep: session.hubManager,
      entries: <Map<String, Object?>>[
        <String, Object?>{
          'name': entry.id,
          'customer': entry.customerId,
          'visit_date': targetDate,
          'sequence_no': targetEntries.length + 1,
          'status': entry.status,
          'notes': entry.notes,
          'starts_on': entry.startsOn,
          'ends_on': entry.endsOn,
        },
      ],
    );
    await _replaceWeekPlan(entries);
    _selectedPlanDate = targetDate;
    _statusMessage = 'Moved ${entry.customerName} to $targetDate.';
    notifyListeners();
  }

  Future<void> deletePlanEntry(PosVisitPlanEntry entry) async {
    if (apiClient == null || isPreview || _offline) {
      _statusMessage =
          'Visit plans can only be edited while the bench is reachable.';
      notifyListeners();
      return;
    }
    await apiClient!.deleteVisitPlanEntry(entry.id);
    _weekPlanEntries = _weekPlanEntries
        .where((PosVisitPlanEntry row) => row.id != entry.id)
        .toList(growable: false);
    await cacheRepository.replaceVisitPlanEntriesForWeek(
      _weekStartForDate(_selectedPlanDate),
      _weekPlanEntries,
    );
    _statusMessage = 'Removed ${entry.customerName} from the visit plan.';
    notifyListeners();
  }

  Future<void> syncSelectedDayData() async {
    if (apiClient == null || isPreview) {
      _statusMessage = 'Day sync requires a live bench connection.';
      notifyListeners();
      return;
    }
    _busy = true;
    _statusMessage = 'Syncing planned customers, prices, and catalog images.';
    notifyListeners();
    try {
      final pack = await apiClient!.getDaySyncPack(
        syncDate: _selectedPlanDate,
        salesRep: session.hubManager,
        includeCustomerDirectory: true,
      );
      if (pack.customerDirectory.isNotEmpty) {
        await cacheRepository.replaceCustomers(pack.customerDirectory);
        _allCustomers = pack.customerDirectory;
        _visibleCustomers =
            _customerSearch.trim().isEmpty
                ? _allCustomers
                : await cacheRepository.searchCustomers(_customerSearch);
      }
      if (pack.catalogGroups.isNotEmpty) {
        await cacheRepository.replaceCatalog(pack.catalogGroups);
        _baseCatalogGroups = pack.catalogGroups;
        _allCategories = _extractCategoryNames(_baseCatalogGroups);
      }
      await cacheRepository.replaceVisitPlanEntriesForDate(
        pack.syncDate,
        pack.planEntries,
      );
      await cacheRepository.saveCustomerPriceSnapshots(
        pack.syncDate,
        pack.customerPriceRows,
      );
      await cacheRepository.replaceCustomerPolicySnapshots(
        pack.syncDate,
        pack.customerPolicies,
      );
      final imageManifest = await _imageSyncService.syncImages(
        entries: pack.imageManifest,
        instanceUrl: instanceUrl,
        databasePath: cacheRepository.databasePath,
      );
      await cacheRepository.upsertImageManifestEntries(imageManifest);
      await cacheRepository.saveDaySyncMetadata(
        syncDate: pack.syncDate,
        customerIds: pack.planEntries
            .map((PosVisitPlanEntry entry) => entry.customerId)
            .toSet()
            .toList(growable: false),
        cursors: pack.syncCursors,
      );
      for (final policy in pack.customerPolicies) {
        _policyByCustomer[policy.customer] = policy;
      }
      _weekPlanEntries = _mergeDayPlanEntries(
        existing: _weekPlanEntries,
        syncDate: pack.syncDate,
        dayEntries: pack.planEntries,
      );
      _lastDaySyncAt = await cacheRepository.readDaySyncSyncedAt(
        _selectedPlanDate,
      );
      if (_selectedCustomer == null) {
        _activeCatalogSourceGroups = _baseCatalogGroups;
        _applyCatalogFilters();
      } else if (_offline || _selectedCustomerOfflineReady) {
        _selectedCustomerOfflineReady = await cacheRepository
            .hasCustomerPriceSync(_selectedPlanDate, _selectedCustomer!.id);
        await _applyOfflineCatalogForSelectedCustomer();
      }
      _offline = false;
      _statusMessage =
          'Synced ${pack.planEntries.length} planned visits and ${pack.customerPriceRows.length} customer price rows for ${pack.syncDate}.';
      PosDebugLog.info(
        'controller.syncSelectedDayData',
        'sync_date=${pack.syncDate} customers=${pack.customerDirectory.length} '
            'plan_entries=${pack.planEntries.length} price_rows=${pack.customerPriceRows.length}',
      );
    } on Exception catch (error) {
      _offline = true;
      _statusMessage =
          'Could not sync the selected day. ${error.toString().trim()}';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void addItem(PosCatalogItem item) {
    final index = _cartLines.indexWhere(
      (CartLine line) => line.itemCode == item.itemCode,
    );
    if (index >= 0) {
      _cartLines[index] = _cartLines[index].copyWith(
        qty: _cartLines[index].qty + 1,
      );
    } else {
      _cartLines.add(
        CartLine(
          itemCode: item.itemCode,
          groupName: item.groupName,
          displayName: item.displayName,
          price: item.price,
          qty: 1,
          taxRows: item.taxRows,
        ),
      );
    }
    _statusMessage = '${item.displayName} added to the cart.';
    notifyListeners();
  }

  void changeLineQuantity(CartLine line, int delta) {
    final index = _cartLines.indexWhere(
      (CartLine entry) => entry.itemCode == line.itemCode,
    );
    if (index < 0) {
      return;
    }
    final nextQty = _cartLines[index].qty + delta;
    if (nextQty <= 0) {
      _cartLines.removeAt(index);
    } else {
      _cartLines[index] = _cartLines[index].copyWith(qty: nextQty);
    }
    notifyListeners();
  }

  void setLineNotes(CartLine line, String value) {
    final index = _cartLines.indexWhere(
      (CartLine entry) => entry.itemCode == line.itemCode,
    );
    if (index < 0) {
      return;
    }
    _cartLines[index] = _cartLines[index].copyWith(notes: value.trim());
    notifyListeners();
  }

  void setOrderNotes(String value) {
    _orderNotes = value;
    notifyListeners();
  }

  Future<void> createCustomer({
    required String customerName,
    String mobileNo = '',
    String emailId = '',
  }) async {
    if (customerName.trim().isEmpty) {
      return;
    }
    PosCustomer customer;
    if (apiClient != null && !isPreview) {
      customer = await apiClient!.createCustomer(
        customerName: customerName.trim(),
        hubManager: session.hubManager,
        mobileNo: mobileNo.trim(),
        emailId: emailId.trim(),
      );
    } else {
      customer = PosCustomer(
        id: 'LOCAL-${DateTime.now().microsecondsSinceEpoch}',
        displayName: customerName.trim(),
        mobileNo: mobileNo.trim(),
        email: emailId.trim(),
        customerCode: '',
        creditLimit: 0,
        outstandingAmount: 0,
        isFrozen: false,
        primaryAddress: '',
        paymentTerm: '',
      );
    }
    final existingIndex = _allCustomers.indexWhere(
      (PosCustomer entry) => entry.id == customer.id,
    );
    if (existingIndex >= 0) {
      _allCustomers[existingIndex] = customer;
    } else {
      _allCustomers = <PosCustomer>[customer, ..._allCustomers];
    }
    await cacheRepository.replaceCustomers(_allCustomers);
    await updateCustomerSearch(_customerSearch);
    await selectCustomer(customer);
    _selectedView = 'Order';
    _statusMessage = 'Customer ${customer.displayName} is ready for ordering.';
    notifyListeners();
  }

  Future<void> parkCurrentOrder() async {
    final validationMessage = _validateOrder(allowBelowMinimum: true);
    if (validationMessage != null) {
      _statusMessage = validationMessage;
      notifyListeners();
      return;
    }

    final payload = _buildOrderPayload(customIsParked: true);
    final order = LocalOrder(
      clientOrderId: '${payload['client_order_id']}',
      customerId: '${payload['customer']}',
      totalAmount: grandTotal,
      payloadJson: jsonEncode(payload),
      status: 'parked',
      updatedAtIso: DateTime.now().toIso8601String(),
      remoteOrderId: _loadedParkedRemoteOrderId,
    );
    await orderRepository.saveParkedOrder(order);
    _parkedOrders = await orderRepository.listParkedOrders();
    await _mergeLocalHistory();
    _statusMessage = 'Order parked locally for later edits.';
    _resetComposer();
    notifyListeners();
  }

  Future<void> loadParkedOrder(LocalOrder order) async {
    final payload = Map<String, dynamic>.from(
      jsonDecode(order.payloadJson) as Map,
    );
    final items = (payload['items'] as List?) ?? const <dynamic>[];
    _selectedCustomer = _allCustomers.firstWhere(
      (PosCustomer customer) => customer.id == order.customerId,
      orElse:
          () => PosCustomer(
            id: order.customerId,
            displayName: order.customerId,
            mobileNo: '',
            email: '',
            customerCode: '',
            creditLimit: 0,
            outstandingAmount: 0,
            isFrozen: false,
            primaryAddress: '',
            paymentTerm: '',
          ),
    );
    _selectedPolicy =
        _policyByCustomer[_selectedCustomer!.id] ??
        await cacheRepository.readCustomerPolicySnapshot(
          _selectedPlanDate,
          _selectedCustomer!.id,
        );
    _selectedIssueStatement = _issueStatements[_selectedCustomer!.id];
    _selectedCustomerOfflineReady = await cacheRepository.hasCustomerPriceSync(
      _selectedPlanDate,
      _selectedCustomer!.id,
    );
    _orderNotes = '${payload['notes'] ?? ''}';
    _loadedParkedOrderId = order.clientOrderId;
    _loadedParkedRemoteOrderId = order.remoteOrderId;
    _cartLines
      ..clear()
      ..addAll(
        items.map((dynamic item) {
          final map = Map<String, dynamic>.from(item as Map);
          return CartLine(
            itemCode: '${map['item_code']}',
            groupName: '${map['group_name'] ?? ''}',
            displayName: '${map['item_name'] ?? map['item_code']}',
            price: double.tryParse('${map['rate'] ?? 0}') ?? 0,
            qty: int.tryParse('${map['qty'] ?? 0}') ?? 0,
            notes: '${map['notes'] ?? ''}',
            taxRows: ((map['tax'] as List?) ?? const <dynamic>[])
                .map((dynamic row) => Map<String, dynamic>.from(row as Map))
                .toList(growable: false),
          );
        }),
      );
    if (_offline) {
      await _applyOfflineCatalogForSelectedCustomer();
    }
    _selectedView = 'Order';
    _statusMessage = 'Loaded parked order ${order.clientOrderId}.';
    notifyListeners();
  }

  Future<void> discardParkedOrder(String clientOrderId) async {
    await orderRepository.deleteParkedOrder(clientOrderId);
    _parkedOrders = await orderRepository.listParkedOrders();
    await _mergeLocalHistory();
    notifyListeners();
  }

  Future<void> submitCurrentOrder() async {
    final validationMessage = _validateOrder();
    if (validationMessage != null) {
      _statusMessage = validationMessage;
      notifyListeners();
      return;
    }

    _busy = true;
    _statusMessage = null;
    notifyListeners();

    final payload = _buildOrderPayload(customIsParked: false);
    final localOrder = LocalOrder(
      clientOrderId: '${payload['client_order_id']}',
      customerId: '${payload['customer']}',
      totalAmount: grandTotal,
      payloadJson: jsonEncode(payload),
      status: 'queued',
      updatedAtIso: DateTime.now().toIso8601String(),
      remoteOrderId: _loadedParkedRemoteOrderId,
    );
    await orderRepository.enqueueSubmit(localOrder);

    if (apiClient != null && !isPreview) {
      try {
        final remoteOrderId = await apiClient!.submitSalesOrder(payload);
        if (remoteOrderId.isNotEmpty) {
          await orderRepository.markSynced(
            localOrder.clientOrderId,
            remoteOrderId,
          );
          _statusMessage = 'Sales order $remoteOrderId submitted successfully.';
          _offline = false;
        }
      } on Exception {
        _offline = true;
        _statusMessage =
            'Backend is unreachable. The order was queued for replay.';
      }
    } else {
      _offline = true;
      _statusMessage =
          'Preview mode queued the order locally. Submit against the live bench on macOS or desktop.';
    }

    _pendingQueue = await orderRepository.readPendingQueue();
    _parkedOrders = await orderRepository.listParkedOrders();
    await _mergeLocalHistory();
    _resetComposer();
    _busy = false;
    notifyListeners();
  }

  Future<void> syncNowFlow({bool showSuccessMessage = true}) async {
    if (apiClient == null || isPreview) {
      return;
    }
    final queue = await orderRepository.readPendingQueue();
    if (queue.isEmpty) {
      if (showSuccessMessage) {
        _statusMessage = 'No queued orders are waiting for replay.';
        notifyListeners();
      }
      return;
    }

    for (final entry in queue) {
      try {
        final payload = Map<String, Object?>.from(
          jsonDecode(entry.payloadJson) as Map,
        );
        final remoteOrderId = await apiClient!.submitSalesOrder(payload);
        if (remoteOrderId.isNotEmpty) {
          await orderRepository.markSynced(entry.clientOrderId, remoteOrderId);
        }
      } on Exception {
        await orderRepository.markRetry(entry.clientOrderId);
        _offline = true;
      }
    }
    _pendingQueue = await orderRepository.readPendingQueue();
    await _mergeLocalHistory();
    if (showSuccessMessage && _pendingQueue.isEmpty) {
      _offline = false;
      _statusMessage = 'Queued orders were replayed successfully.';
    }
    notifyListeners();
  }

  Future<bool> prepareLogout() async {
    if (apiClient != null && !isPreview) {
      await syncNowFlow(showSuccessMessage: false);
      if (_pendingQueue.isNotEmpty) {
        _statusMessage =
            'Queued orders still need the backend. Sync them before logging out.';
        notifyListeners();
        return false;
      }
    }
    return true;
  }

  Future<void> refreshFromBackend({bool showMessage = true}) async {
    if (apiClient == null || isPreview) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final customers = await apiClient!.getCustomers(
        hubManager: session.hubManager,
        searchText: '',
      );
      final catalog = await apiClient!.getCatalog();
      final history = await apiClient!.getHistory(
        hubManager: session.hubManager,
      );
      final account = await apiClient!.getAccount(
        hubManager: session.hubManager,
      );
      _taxRows = await apiClient!.getTaxes();

      await cacheRepository.replaceCustomers(customers);
      await cacheRepository.replaceCatalog(catalog);
      await cacheRepository.saveHistorySnapshot(history);
      await cacheRepository.saveAccountSnapshot(account);
      await cacheRepository.saveTaxSnapshot(_taxRows);

      _allCustomers = customers;
      _visibleCustomers =
          _customerSearch.trim().isEmpty
              ? customers
              : await cacheRepository.searchCustomers(_customerSearch);
      _baseCatalogGroups = catalog;
      _history = history;
      _account = account;
      _offline = false;

      if (_selectedCustomer == null) {
        _activeCatalogSourceGroups = _baseCatalogGroups;
        _applyCatalogFilters();
      } else {
        try {
          final liveCatalog = await apiClient!.getCatalog(
            customer: _pricingCustomerId(),
          );
          _activeCatalogSourceGroups = liveCatalog;
          _applyCatalogFilters();
        } on Exception {
          await _applyOfflineCatalogForSelectedCustomer();
        }
      }

      PosDebugLog.info(
        'controller.refreshFromBackend',
        'hub_manager=${session.hubManager} fetched=${PosDebugLog.summarizeCustomers(customers)} '
            'visible=${PosDebugLog.summarizeCustomers(_visibleCustomers)} '
            'catalog_groups=${catalog.length} history=${history.length} taxes=${_taxRows.length}',
      );
      if (showMessage) {
        _statusMessage = 'Catalog and customer cache refreshed from the bench.';
      }
      await _mergeLocalHistory();
    } on Exception {
      _offline = true;
      if (showMessage) {
        _statusMessage =
            'Unable to refresh from the bench. Showing the local cache.';
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _dateOnly() => DateTime.now().toIso8601String().split('T').first;

  String _weekStartForDate(String isoDate) {
    final resolved = DateTime.parse(isoDate);
    final monday = resolved.subtract(Duration(days: resolved.weekday - 1));
    return monday.toIso8601String().split('T').first;
  }

  String _addDays(String isoDate, int days) {
    return DateTime.parse(
      isoDate,
    ).add(Duration(days: days)).toIso8601String().split('T').first;
  }

  String? _pricingCustomerId() {
    final customer = _selectedCustomer;
    if (customer == null) {
      return null;
    }
    return customer.customerCode.isNotEmpty
        ? customer.customerCode
        : customer.id;
  }

  Map<String, Object?> _buildOrderPayload({required bool customIsParked}) {
    return <String, Object?>{
      'client_order_id':
          _loadedParkedOrderId ??
          'NEURADIX-${DateTime.now().microsecondsSinceEpoch}',
      'customer': _selectedCustomer!.id,
      'hub_manager': session.hubManager,
      if (_loadedParkedRemoteOrderId != null &&
          _loadedParkedRemoteOrderId!.isNotEmpty)
        'custom_previous_id': _loadedParkedRemoteOrderId,
      'transaction_date': _dateOnly(),
      'delivery_date': _dateOnly(),
      'notes': _orderNotes.trim(),
      'custom_is_parked': customIsParked,
      'client_platform': defaultTargetPlatform.name,
      'order_taxes': _taxRows,
      'items': _cartLines
          .map(
            (CartLine line) => <String, Object?>{
              'item_code': line.itemCode,
              'item_name': line.displayName,
              'group_name': line.groupName,
              'qty': line.qty,
              'rate': line.price,
              'notes': line.notes,
              'tax': line.taxRows,
            },
          )
          .toList(growable: false),
    };
  }

  String? _validateOrder({bool allowBelowMinimum = false}) {
    if (_selectedCustomer == null) {
      return 'Select a customer before creating the order.';
    }
    if (_cartLines.isEmpty) {
      return 'Add at least one item to the cart.';
    }
    if (_offline && !_selectedCustomerOfflineReady) {
      return 'This customer is not synced for offline pricing. Use Plan & Sync before placing the order offline.';
    }
    final policy = _selectedPolicy;
    if (policy != null && policy.isFrozen) {
      return 'This customer is frozen and cannot place an order.';
    }
    if (!allowBelowMinimum && policy != null && policy.minimumOrderRequired) {
      final belowMinimum = subtotal < policy.minimumOrderAmount;
      final lineNoteBypassAllowed =
          policy.notesBypassMinimum &&
          _cartLines.every((CartLine line) => line.notes.trim().isNotEmpty);
      if (belowMinimum && !lineNoteBypassAllowed) {
        return 'Minimum order is ${policy.minimumOrderAmount.toStringAsFixed(2)} ${bootstrap.currencySymbol}. Add notes to every item to bypass or increase the order value.';
      }
    }
    return null;
  }

  Future<void> _mergeLocalHistory() async {
    final localOrders = await orderRepository.listOrders();
    final localHistory = localOrders
        .map((LocalOrder order) {
          final payload = Map<String, dynamic>.from(
            jsonDecode(order.payloadJson) as Map,
          );
          final items = (payload['items'] as List?) ?? const <dynamic>[];
          return PosHistoryOrder(
            id:
                order.remoteOrderId?.isNotEmpty == true
                    ? order.remoteOrderId!
                    : order.clientOrderId,
            customer: _customerNameForId(order.customerId),
            transactionDate: order.updatedAtIso.split('T').first,
            grandTotal: order.totalAmount,
            status:
                order.status == 'synced'
                    ? 'Submitted'
                    : order.status[0].toUpperCase() + order.status.substring(1),
            isParked: order.status == 'parked',
            isLocalOnly:
                order.remoteOrderId == null || order.remoteOrderId!.isEmpty,
            items: items
                .map(
                  (dynamic item) => PosHistoryOrderLine.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false);

    final merged = <PosHistoryOrder>[
      ...localHistory,
      ..._history.where(
        (PosHistoryOrder order) =>
            localHistory.every((PosHistoryOrder local) => local.id != order.id),
      ),
    ];
    merged.sort(
      (PosHistoryOrder left, PosHistoryOrder right) =>
          right.transactionDate.compareTo(left.transactionDate),
    );
    _history = merged;
  }

  Future<void> _applyOfflineCatalogForSelectedCustomer() async {
    final customer = _selectedCustomer;
    if (customer == null) {
      _activeCatalogSourceGroups = _baseCatalogGroups;
      _applyCatalogFilters();
      return;
    }
    final cachedPolicy = await cacheRepository.readCustomerPolicySnapshot(
      _selectedPlanDate,
      customer.id,
    );
    if (cachedPolicy != null) {
      _selectedPolicy = cachedPolicy;
      _policyByCustomer[customer.id] = cachedPolicy;
    }
    _selectedIssueStatement ??= await cacheRepository.readIssueStatement(
      customer.id,
    );
    _selectedCustomerOfflineReady = await cacheRepository.hasCustomerPriceSync(
      _selectedPlanDate,
      customer.id,
    );
    if (_selectedCustomerOfflineReady) {
      _activeCatalogSourceGroups = await cacheRepository.readCatalog(
        syncDate: _selectedPlanDate,
        customerId: customer.id,
      );
      _applyCatalogFilters();
      _statusMessage =
          'Loaded offline price pack for ${customer.displayName} on $_selectedPlanDate.';
    } else {
      _activeCatalogSourceGroups = const <PosCatalogGroup>[];
      _applyCatalogFilters();
      _statusMessage =
          'This customer is not synced for offline pricing. Open Plan & Sync and run Sync Data.';
    }
  }

  Future<void> _replaceWeekPlan(List<PosVisitPlanEntry> entries) async {
    final weekStart =
        entries.isEmpty
            ? _weekStartForDate(_selectedPlanDate)
            : _weekStartForDate(entries.first.visitDate);
    _weekPlanEntries = entries;
    await cacheRepository.replaceVisitPlanEntriesForWeek(weekStart, entries);
  }

  List<PosVisitPlanEntry> _mergeDayPlanEntries({
    required List<PosVisitPlanEntry> existing,
    required String syncDate,
    required List<PosVisitPlanEntry> dayEntries,
  }) {
    final retained = existing
        .where((PosVisitPlanEntry entry) => entry.visitDate != syncDate)
        .toList(growable: false);
    return <PosVisitPlanEntry>[...retained, ...dayEntries]
      ..sort((PosVisitPlanEntry left, PosVisitPlanEntry right) {
        final dateCompare = left.visitDate.compareTo(right.visitDate);
        if (dateCompare != 0) {
          return dateCompare;
        }
        final sequenceCompare = left.sequenceNo.compareTo(right.sequenceNo);
        if (sequenceCompare != 0) {
          return sequenceCompare;
        }
        return left.customerName.compareTo(right.customerName);
      });
  }

  List<PosVisitPlanEntry> _entriesForDate(String isoDate) {
    return _weekPlanEntries
      .where((PosVisitPlanEntry entry) => entry.visitDate == isoDate)
      .toList(growable: false)..sort(
      (PosVisitPlanEntry left, PosVisitPlanEntry right) =>
          left.sequenceNo.compareTo(right.sequenceNo),
    );
  }

  String _customerNameForId(String customerId) {
    final customer = _allCustomers.cast<PosCustomer?>().firstWhere(
      (PosCustomer? entry) => entry?.id == customerId,
      orElse: () => null,
    );
    return customer?.displayName ?? customerId;
  }

  List<String> _extractCategoryNames(List<PosCatalogGroup> groups) {
    return groups
        .map((PosCatalogGroup group) => group.groupName)
        .where((String name) => name.trim().isNotEmpty)
        .toList(growable: false);
  }

  void _applyCatalogFilters() {
    final normalizedSearch = _catalogSearch.trim().toLowerCase();
    final filtered = _activeCatalogSourceGroups
        .where(
          (PosCatalogGroup group) =>
              _selectedCategory == null || group.groupName == _selectedCategory,
        )
        .map((PosCatalogGroup group) {
          final items = group.items
              .where(
                (PosCatalogItem item) =>
                    normalizedSearch.isEmpty ||
                    group.groupName.toLowerCase().contains(normalizedSearch) ||
                    item.displayName.toLowerCase().contains(normalizedSearch),
              )
              .toList(growable: false);
          return group.copyWith(items: items);
        })
        .where((PosCatalogGroup group) => group.items.isNotEmpty)
        .toList(growable: false);
    _catalogGroups = filtered;
    _allCategories = _extractCategoryNames(_baseCatalogGroups);
  }

  void clearStatusMessage() {
    _statusMessage = null;
    notifyListeners();
  }

  void _resetComposer() {
    _cartLines.clear();
    _selectedCustomer = null;
    _selectedPolicy = null;
    _selectedIssueStatement = null;
    _selectedCustomerOfflineReady = false;
    _orderNotes = '';
    _loadedParkedOrderId = null;
    _loadedParkedRemoteOrderId = null;
    _activeCatalogSourceGroups = _baseCatalogGroups;
    _applyCatalogFilters();
  }
}
