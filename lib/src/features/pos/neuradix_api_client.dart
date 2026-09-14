import 'dart:convert';

import 'package:http/http.dart' as http;

import '../hosted/hosted_models.dart';
import 'pos_debug_log.dart';
import 'pos_models.dart';

class NeuradixApiException implements Exception {
  const NeuradixApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NeuradixApiClient {
  NeuradixApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    String? apiKey,
    String? apiSecret,
  }) : _httpClient = httpClient ?? http.Client(),
       _apiKey = apiKey,
       _apiSecret = apiSecret;

  final String baseUrl;
  final http.Client _httpClient;

  String? _apiKey;
  String? _apiSecret;

  Future<PosBootstrapBundle> fetchBootstrap() async {
    await ping();
    final platformPayload = await _callMethod(
      'neuradix.api.v1.bootstrap.get_bootstrap',
      authenticated: false,
    );
    final clientPayload = await _callMethod(
      'neuradix_cassarcamilleri.api.v1.bootstrap.get_client_bootstrap',
      authenticated: false,
    );
    return PosBootstrapBundle.fromResponses(
      _unwrapMessageMap(platformPayload),
      _unwrapMessageMap(clientPayload),
    );
  }

  Future<PosBootstrapBundle> fetchHostedBootstrap() async {
    await ping();
    final platformPayload = await _callMethod(
      'neuradix.api.v1.bootstrap.get_bootstrap',
      authenticated: false,
    );
    return PosBootstrapBundle.fromPlatform(_unwrapMessageMap(platformPayload));
  }

  Future<void> ping() async {
    final response = await _httpClient.get(_buildUri('api/method/ping'));
    if (response.statusCode >= 400) {
      throw NeuradixApiException('Unable to reach the bench at $baseUrl.');
    }
  }

  Future<PosLoginSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _httpClient.post(
      _buildUri('api/method/neuradix.api.v1.bootstrap.login'),
      body: <String, String>{'usr': username, 'pwd': password},
    );

    final payload = _decodeResponse(response);
    final message = Map<String, dynamic>.from(
      (payload['message'] as Map?) ?? payload,
    );
    final apiKey = '${message['api_key'] ?? ''}';
    final apiSecret = '${message['api_secret'] ?? ''}';
    if (apiKey.isEmpty || apiSecret.isEmpty) {
      throw const NeuradixApiException(
        'Login succeeded but API credentials were missing.',
      );
    }

    _apiKey = apiKey;
    _apiSecret = apiSecret;

    final email = '${message['email'] ?? username}';
    final hubManager =
        '${message['hub_manager'] ?? message['email'] ?? message['username'] ?? username}';
    return PosLoginSession(
      username: '${message['username'] ?? username}',
      email: email,
      apiKey: apiKey,
      apiSecret: apiSecret,
      hubManager: hubManager,
      deploymentMode: 'external_backend',
    );
  }

  Future<HostedAuthResult> registerHostedBusiness({
    required String businessName,
    required String fullName,
    required String email,
    required String password,
    required String deviceId,
    required String deviceName,
    required String planType,
  }) async {
    final response = await _callMethod(
      'neuradix.api.v1.auth.register_business',
      method: 'POST',
      authenticated: false,
      body: <String, String>{
        'business_name': businessName,
        'full_name': fullName,
        'email': email,
        'password': password,
        'device_id': deviceId,
        'device_name': deviceName,
        'plan_type': planType,
      },
    );
    return _parseHostedAuthResult(response);
  }

  Future<HostedAuthAttempt> tryRegisterHostedBusiness({
    required String businessName,
    required String fullName,
    required String email,
    required String password,
    required String deviceId,
    required String deviceName,
    required String planType,
  }) async {
    final outcome = await _callMethodOutcome(
      'neuradix.api.v1.auth.register_business',
      method: 'POST',
      authenticated: false,
      body: <String, String>{
        'business_name': businessName,
        'full_name': fullName,
        'email': email,
        'password': password,
        'device_id': deviceId,
        'device_name': deviceName,
        'plan_type': planType,
      },
    );
    if (outcome.error != null) {
      return HostedAuthAttempt(error: outcome.error);
    }
    return HostedAuthAttempt(auth: _parseHostedAuthResult(outcome.payload!));
  }

  Future<HostedAuthResult> loginHosted({
    required String email,
    required String password,
    required String deviceId,
    required String deviceName,
  }) async {
    final response = await _callMethod(
      'neuradix.api.v1.auth.login_hosted',
      method: 'POST',
      authenticated: false,
      body: <String, String>{
        'usr': email,
        'pwd': password,
        'device_id': deviceId,
        'device_name': deviceName,
      },
    );
    return _parseHostedAuthResult(response);
  }

  Future<HostedAuthAttempt> tryLoginHosted({
    required String email,
    required String password,
    required String deviceId,
    required String deviceName,
  }) async {
    final outcome = await _callMethodOutcome(
      'neuradix.api.v1.auth.login_hosted',
      method: 'POST',
      authenticated: false,
      body: <String, String>{
        'usr': email,
        'pwd': password,
        'device_id': deviceId,
        'device_name': deviceName,
      },
    );
    if (outcome.error != null) {
      return HostedAuthAttempt(error: outcome.error);
    }
    return HostedAuthAttempt(auth: _parseHostedAuthResult(outcome.payload!));
  }

  Future<Map<String, dynamic>> forgotPassword(String user) {
    return _callMethod(
      'neuradix.api.v1.support.forgot_password',
      method: 'POST',
      authenticated: false,
      body: <String, String>{'user': user},
    );
  }

  Future<Map<String, dynamic>> getPrivacyTerms() {
    return _callMethod(
      'neuradix.api.v1.support.privacy_policy_and_terms',
      authenticated: false,
    );
  }

  Future<Map<String, dynamic>> changePassword({
    required String username,
    required String password,
  }) {
    return _callMethod(
      'neuradix.api.v1.support.change_password',
      method: 'POST',
      body: <String, String>{'usr': username, 'pwd': password},
    );
  }

  Future<List<PosCustomer>> getCustomers({
    required String hubManager,
    String searchText = '',
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.customers.get_customers',
      queryParameters: <String, String>{
        'hub_manager': hubManager,
        if (searchText.trim().isNotEmpty) 'search_text': searchText.trim(),
      },
    );
    final message = _unwrapMessageMap(payload);
    final rows = ((message['customers'] as List?) ?? const <dynamic>[])
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    PosDebugLog.info(
      'api.getCustomers',
      'hub_manager=$hubManager search="${searchText.trim()}" ${PosDebugLog.summarizeCustomerMaps(rows)}',
    );
    return rows
        .map((Map<String, dynamic> row) => PosCustomer.fromApi(row))
        .toList(growable: false);
  }

  Future<PosCustomer> createCustomer({
    required String customerName,
    required String hubManager,
    String mobileNo = '',
    String emailId = '',
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.customers.create_customer',
      method: 'POST',
      body: <String, String>{
        'customer_name': customerName,
        'mobile_no': mobileNo,
        'email_id': emailId,
        'hub_manager': hubManager,
      },
    );
    final message = _unwrapMessageMap(payload);
    final customerJson = Map<String, dynamic>.from(
      (message['customer'] as Map?) ?? message,
    );
    final existingCustomerName = '${message['message'] ?? ''}';
    PosDebugLog.info(
      'api.createCustomer',
      'hub_manager=$hubManager customer_name="$customerName" mobile="$mobileNo" result=${PosDebugLog.summarizeCustomerMaps(<Map<String, dynamic>>[customerJson])}',
    );
    return PosCustomer(
      id: '${customerJson['name'] ?? customerName}',
      displayName: '${customerJson['customer_name'] ?? customerName}',
      mobileNo: '${customerJson['mobile_no'] ?? mobileNo}',
      email: '${customerJson['email_id'] ?? emailId}',
      customerCode: '${customerJson['custom_customer_id'] ?? ''}',
      creditLimit:
          double.tryParse(
            '${customerJson['custom_customer_credit_limit'] ?? 0}',
          ) ??
          0,
      outstandingAmount:
          double.tryParse(
            '${customerJson['custom_customer_outstanding'] ?? 0}',
          ) ??
          0,
      isFrozen:
          customerJson['custom_frozen_customer'] == true ||
          customerJson['custom_frozen_customer'] == 1 ||
          customerJson['custom_frozen_customer'] == '1',
      primaryAddress: '${customerJson['primary_address'] ?? ''}',
      paymentTerm:
          existingCustomerName.contains('already present')
              ? '${customerJson['custom_payment_term'] ?? ''}'
              : '${customerJson['custom_payment_term'] ?? ''}',
    );
  }

  Future<PosCustomer?> getCustomerByMobile(String mobileNo) async {
    final payload = await _callMethod(
      'neuradix.api.v1.customers.get_customer_by_mobile',
      queryParameters: <String, String>{'mobile_no': mobileNo},
    );
    final message = _unwrapMessageMap(payload);
    final customers = ((message['customer'] as List?) ?? const <dynamic>[])
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    PosDebugLog.info(
      'api.getCustomerByMobile',
      'mobile_no="$mobileNo" ${PosDebugLog.summarizeCustomerMaps(customers)}',
    );
    if (customers.isEmpty) {
      return null;
    }
    return PosCustomer.fromApi(customers.first);
  }

  Future<List<PosCatalogGroup>> getCatalog({String? customer}) async {
    final payload = await _callMethod(
      'neuradix.api.v1.catalog.get_catalog',
      queryParameters: <String, String>{
        if (customer != null && customer.isNotEmpty) 'customer': customer,
      },
    );
    final rows = (payload['message'] as List?) ?? const <dynamic>[];
    return rows
        .map(
          (dynamic row) =>
              PosCatalogGroup.fromApi(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<List<PosVisitPlanEntry>> getWeekPlan({
    required String weekStart,
    String? salesRep,
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.visit_plan.get_week_plan',
      queryParameters: <String, String>{
        'week_start': weekStart,
        if (salesRep != null && salesRep.isNotEmpty) 'sales_rep': salesRep,
      },
    );
    final message = _unwrapMessageMap(payload);
    final rows = ((message['entries'] as List?) ?? const <dynamic>[])
        .map(
          (dynamic row) =>
              PosVisitPlanEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
    PosDebugLog.info(
      'api.getWeekPlan',
      'week_start=$weekStart sales_rep=${salesRep ?? ''} count=${rows.length}',
    );
    return rows;
  }

  Future<List<PosVisitPlanEntry>> upsertVisitPlanEntries({
    required String salesRep,
    required List<Map<String, Object?>> entries,
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.visit_plan.upsert_entries',
      method: 'POST',
      body: <String, String>{
        'sales_rep': salesRep,
        'payload': jsonEncode(<String, Object?>{'entries': entries}),
      },
    );
    final message = _unwrapMessageMap(payload);
    final rows = ((message['entries'] as List?) ?? const <dynamic>[])
        .map(
          (dynamic row) =>
              PosVisitPlanEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
    PosDebugLog.info(
      'api.upsertVisitPlanEntries',
      'sales_rep=$salesRep submitted=${entries.length} returned=${rows.length}',
    );
    return rows;
  }

  Future<void> deleteVisitPlanEntry(String entryId) async {
    await _callMethod(
      'neuradix.api.v1.visit_plan.delete_entry',
      method: 'POST',
      body: <String, String>{'entry_id': entryId},
    );
    PosDebugLog.info('api.deleteVisitPlanEntry', 'entry_id=$entryId');
  }

  Future<PosOfflineDaySyncPack> getDaySyncPack({
    required String syncDate,
    String? salesRep,
    bool includeCustomerDirectory = true,
    String? customerModifiedSince,
    String? catalogModifiedSince,
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.offline_sync.get_day_sync_pack',
      queryParameters: <String, String>{
        'date': syncDate,
        if (salesRep != null && salesRep.isNotEmpty) 'sales_rep': salesRep,
        'include_customer_directory': includeCustomerDirectory ? '1' : '0',
        if (customerModifiedSince != null && customerModifiedSince.isNotEmpty)
          'customer_modified_since': customerModifiedSince,
        if (catalogModifiedSince != null && catalogModifiedSince.isNotEmpty)
          'catalog_modified_since': catalogModifiedSince,
      },
    );
    final pack = PosOfflineDaySyncPack.fromJson(
      Map<String, dynamic>.from((payload['message'] as Map?) ?? payload),
    );
    PosDebugLog.info(
      'api.getDaySyncPack',
      'sync_date=$syncDate plan_entries=${pack.planEntries.length} '
          'customers=${pack.customerDirectory.length} '
          'price_rows=${pack.customerPriceRows.length}',
    );
    return pack;
  }

  Future<List<Map<String, dynamic>>> getTaxes() async {
    final payload = await _callMethod('neuradix.api.v1.taxes.get_sales_taxes');
    final rows = (payload['message'] as List?) ?? const <dynamic>[];
    return rows
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<PosHistoryOrder>> getHistory({
    required String hubManager,
    String? customer,
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.history.get_sales_history',
      queryParameters: <String, String>{
        'hub_manager': hubManager,
        if (customer != null && customer.isNotEmpty) 'customer': customer,
      },
    );
    final rows = (payload['message'] as List?) ?? const <dynamic>[];
    return rows
        .map(
          (dynamic row) =>
              PosHistoryOrder.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<PosAccountSummary> getAccount({required String hubManager}) async {
    final payload = await _callMethod(
      'neuradix.api.v1.account.get_account',
      queryParameters: <String, String>{'hub_manager': hubManager},
    );
    return PosAccountSummary.fromJson(
      Map<String, dynamic>.from((payload['message'] as Map?) ?? payload),
    );
  }

  Future<PosCustomerPolicy> getCustomerPolicy(String customer) async {
    final payload = await _callMethod(
      'neuradix_cassarcamilleri.api.v1.account.get_customer_policy',
      queryParameters: <String, String>{'customer': customer},
    );
    return PosCustomerPolicy.fromJson(
      Map<String, dynamic>.from((payload['message'] as Map?) ?? payload),
    );
  }

  Future<PosIssueStatement> getIssueStatement(String customer) async {
    final payload = await _callMethod(
      'neuradix_cassarcamilleri.api.v1.account.get_issue_statement_detail',
      queryParameters: <String, String>{'customer': customer},
    );
    return PosIssueStatement.fromJson(
      Map<String, dynamic>.from((payload['message'] as Map?) ?? payload),
    );
  }

  Future<String> submitSalesOrder(Map<String, Object?> payload) async {
    final response = await _callMethod(
      'neuradix.api.v1.orders.submit_sales_order',
      method: 'POST',
      body: <String, String>{'payload': jsonEncode(payload)},
    );
    final message = _unwrapMessageMap(response);
    final status = '${message['status'] ?? ''}';
    if (status != 'submitted' && status != 'duplicate') {
      throw const NeuradixApiException(
        'The backend did not accept the sales order.',
      );
    }
    return '${message['sales_order_name'] ?? ''}';
  }

  Future<HostedBusinessProfile> getCurrentBusiness() async {
    final payload = await _callMethod(
      'neuradix.api.v1.business.get_current_business',
    );
    return HostedBusinessProfile.fromJson(_unwrapMessageMap(payload));
  }

  Future<HostedBusinessProfile> startUpgrade() async {
    final payload = await _callMethod(
      'neuradix.api.v1.subscription.start_upgrade',
      method: 'POST',
    );
    final message = _unwrapMessageMap(payload);
    return HostedBusinessProfile.fromJson(<String, dynamic>{
      'business': message['business'],
      'plan_type': message['plan_type'],
      'subscription_status': message['subscription_status'],
    });
  }

  Future<List<HostedCustomer>> listHostedCustomers() async {
    final payload = await _callMethod(
      'neuradix.api.v1.business.list_customers',
    );
    final message = _unwrapMessageMap(payload);
    final rows = (message['customers'] as List?) ?? const <dynamic>[];
    return rows
        .map(
          (dynamic row) =>
              HostedCustomer.fromApi(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<HostedCustomer> upsertHostedCustomer(HostedCustomer customer) async {
    final payload = await _callMethod(
      'neuradix.api.v1.business.upsert_customer',
      method: 'POST',
      body: <String, String>{
        'customer_id': customer.customerId,
        'customer_name': customer.displayName,
        'customer_code': customer.customerCode,
        'mobile_no': customer.mobileNo,
        'email_id': customer.emailId,
        'primary_address': customer.primaryAddress,
      },
    );
    final message = _unwrapMessageMap(payload);
    return HostedCustomer.fromApi(
      Map<String, dynamic>.from((message['customer'] as Map?) ?? message),
    );
  }

  Future<List<HostedInventoryItem>> listHostedInventoryItems() async {
    final payload = await _callMethod('neuradix.api.v1.inventory.list_items');
    final message = _unwrapMessageMap(payload);
    final rows = (message['items'] as List?) ?? const <dynamic>[];
    return rows
        .map(
          (dynamic row) => HostedInventoryItem.fromApi(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<HostedInventoryItem> upsertHostedInventoryItem(
    HostedInventoryItem item, {
    String? imageUploadBase64,
    String? imageUploadFileName,
    String? imageUploadMimeType,
  }) async {
    final bodyPayload = <String, Object?>{...item.toApiPayload()};
    if (imageUploadBase64 != null &&
        imageUploadBase64.isNotEmpty &&
        imageUploadFileName != null &&
        imageUploadFileName.isNotEmpty) {
      final uploadResponse = await uploadHostedInventoryImage(
        fileName: imageUploadFileName,
        contentBase64: imageUploadBase64,
        mimeType: imageUploadMimeType ?? 'application/octet-stream',
      );
      bodyPayload['image_url'] = uploadResponse['file_url'] ?? item.imageUrl;
    }
    final payload = await _callMethod(
      'neuradix.api.v1.inventory.upsert_item',
      method: 'POST',
      body: <String, String>{'payload': jsonEncode(bodyPayload)},
    );
    final message = _unwrapMessageMap(payload);
    return HostedInventoryItem.fromApi(
      Map<String, dynamic>.from((message['item'] as Map?) ?? message),
    );
  }

  Future<Map<String, dynamic>> uploadHostedInventoryImage({
    required String fileName,
    required String contentBase64,
    required String mimeType,
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.inventory.upload_item_image',
      method: 'POST',
      body: <String, String>{
        'file_name': fileName,
        'content_base64': contentBase64,
        'mime_type': mimeType,
      },
    );
    return _unwrapMessageMap(payload);
  }

  Future<void> deleteHostedInventoryItem(String itemId) async {
    await _callMethod(
      'neuradix.api.v1.inventory.delete_item',
      method: 'POST',
      body: <String, String>{'item_id': itemId},
    );
  }

  Future<HostedSaleRecord> submitHostedSale(
    HostedSaleRecord sale, {
    String deviceId = '',
  }) async {
    final payload = await _callMethod(
      'neuradix.api.v1.sales.submit_sale',
      method: 'POST',
      body: <String, String>{
        'payload': jsonEncode(sale.toApiPayload()),
        'device_id': deviceId,
      },
    );
    final message = _unwrapMessageMap(payload);
    return HostedSaleRecord.fromJson(<String, dynamic>{
      'sale_id': message['client_sale_id'] ?? sale.saleId,
      'remote_sale_id': message['sale_id'] ?? '',
      'customer_id': sale.customerId,
      'customer_name': message['customer_name'] ?? sale.customerName,
      'posting_date': message['posting_date'] ?? sale.postingDate,
      'total_amount': message['total_amount'] ?? sale.totalAmount,
      'status': message['status'] ?? 'submitted',
      'items': sale.items.map((HostedSaleLine item) => item.toJson()).toList(),
    });
  }

  Future<List<HostedSaleRecord>> getHostedSalesHistory() async {
    final payload = await _callMethod(
      'neuradix.api.v1.sales.get_sales_history',
    );
    final message = _unwrapMessageMap(payload);
    final rows = (message['sales'] as List?) ?? const <dynamic>[];
    return rows
        .map(
          (dynamic row) =>
              HostedSaleRecord.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> importLocalBusinessData(
    Map<String, Object?> payload, {
    String deviceId = '',
  }) async {
    final response = await _callMethod(
      'neuradix.api.v1.migration.import_local_business_data',
      method: 'POST',
      body: <String, String>{
        'payload': jsonEncode(payload),
        'device_id': deviceId,
      },
    );
    return _unwrapMessageMap(response);
  }

  Future<Map<String, dynamic>> _callMethod(
    String methodName, {
    Map<String, String>? queryParameters,
    Map<String, String>? body,
    String method = 'GET',
    bool authenticated = true,
  }) async {
    final response = await _sendMethodRequest(
      methodName,
      queryParameters: queryParameters,
      body: body,
      method: method,
      authenticated: authenticated,
    );
    return _decodeResponse(response);
  }

  Future<_MethodCallOutcome> _callMethodOutcome(
    String methodName, {
    Map<String, String>? queryParameters,
    Map<String, String>? body,
    String method = 'GET',
    bool authenticated = true,
  }) async {
    try {
      final response = await _sendMethodRequest(
        methodName,
        queryParameters: queryParameters,
        body: body,
        method: method,
        authenticated: authenticated,
      );
      return _decodeResponseOutcome(response);
    } on Exception catch (error) {
      return _MethodCallOutcome(error: error);
    }
  }

  Future<http.Response> _sendMethodRequest(
    String methodName, {
    Map<String, String>? queryParameters,
    Map<String, String>? body,
    String method = 'GET',
    bool authenticated = true,
  }) {
    final uri = _buildUri(
      'api/method/$methodName',
      queryParameters: queryParameters,
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      if (authenticated && _apiKey != null && _apiSecret != null)
        'Authorization': 'token $_apiKey:$_apiSecret',
    };
    if (method == 'POST') {
      return _httpClient.post(uri, headers: headers, body: body);
    }
    return _httpClient.get(uri, headers: headers);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.trim().isEmpty) {
      if (response.statusCode >= 400) {
        throw NeuradixApiException(
          'Backend request failed with status ${response.statusCode}.',
        );
      }
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      if (response.statusCode >= 400) {
        final message = _extractBackendErrorMessage(decoded).trim();
        if (message.isNotEmpty) {
          throw NeuradixApiException(message);
        }
        throw NeuradixApiException(
          'Backend request failed with status ${response.statusCode}.',
        );
      }
      if (decoded['exc'] != null) {
        throw NeuradixApiException('${decoded['exc']}');
      }
      return decoded;
    }
    if (response.statusCode >= 400) {
      throw NeuradixApiException(
        'Backend request failed with status ${response.statusCode}.',
      );
    }
    return <String, dynamic>{'message': decoded};
  }

  _MethodCallOutcome _decodeResponseOutcome(http.Response response) {
    if (response.body.trim().isEmpty) {
      if (response.statusCode >= 400) {
        return _MethodCallOutcome(
          error: NeuradixApiException(
            'Backend request failed with status ${response.statusCode}.',
          ),
        );
      }
      return const _MethodCallOutcome(payload: <String, dynamic>{});
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      if (response.statusCode >= 400) {
        final message = _extractBackendErrorMessage(decoded).trim();
        return _MethodCallOutcome(
          error: NeuradixApiException(
            message.isNotEmpty
                ? message
                : 'Backend request failed with status ${response.statusCode}.',
          ),
        );
      }
      if (decoded['exc'] != null) {
        return _MethodCallOutcome(
          error: NeuradixApiException(
            _extractExceptionMessage(decoded['exc']) ?? '${decoded['exc']}',
          ),
        );
      }
      return _MethodCallOutcome(payload: decoded);
    }
    if (response.statusCode >= 400) {
      return _MethodCallOutcome(
        error: NeuradixApiException(
          'Backend request failed with status ${response.statusCode}.',
        ),
      );
    }
    return _MethodCallOutcome(payload: <String, dynamic>{'message': decoded});
  }

  String _extractBackendErrorMessage(Map<String, dynamic> decoded) {
    final directMessage = '${decoded['message'] ?? ''}'.trim();
    if (directMessage.isNotEmpty && directMessage != 'null') {
      return directMessage;
    }

    final serverMessage = _extractServerMessage(decoded['_server_messages']);
    if (serverMessage != null && serverMessage.isNotEmpty) {
      return serverMessage;
    }

    final exceptionMessage = _extractExceptionMessage(decoded['exception']);
    if (exceptionMessage != null && exceptionMessage.isNotEmpty) {
      return exceptionMessage;
    }

    final excType = '${decoded['exc_type'] ?? ''}'.trim();
    if (excType.isNotEmpty && excType != 'null') {
      return excType;
    }

    return '';
  }

  String? _extractServerMessage(Object? rawServerMessages) {
    if (rawServerMessages is! String || rawServerMessages.trim().isEmpty) {
      return null;
    }

    try {
      final decodedList = jsonDecode(rawServerMessages);
      if (decodedList is! List) {
        return null;
      }

      Map<String, dynamic>? selectedMessage;
      for (final dynamic entry in decodedList) {
        Map<String, dynamic>? parsedEntry;
        if (entry is String) {
          final decodedEntry = jsonDecode(entry);
          if (decodedEntry is Map<String, dynamic>) {
            parsedEntry = decodedEntry;
          }
        } else if (entry is Map<String, dynamic>) {
          parsedEntry = entry;
        }

        if (parsedEntry == null) {
          continue;
        }

        selectedMessage = parsedEntry;
        if (parsedEntry['raise_exception'] == 1 ||
            parsedEntry['raise_exception'] == true ||
            '${parsedEntry['indicator']}'.toLowerCase() == 'red') {
          break;
        }
      }

      if (selectedMessage == null) {
        return null;
      }

      return _stripHtml('${selectedMessage['message'] ?? ''}');
    } catch (_) {
      return null;
    }
  }

  String? _extractExceptionMessage(Object? rawException) {
    final exceptionText = '${rawException ?? ''}'.trim();
    if (exceptionText.isEmpty || exceptionText == 'null') {
      return null;
    }

    final lastLine = exceptionText
        .split('\n')
        .lastWhere((String line) => line.trim().isNotEmpty, orElse: () => '');
    final colonIndex = lastLine.lastIndexOf(':');
    if (colonIndex >= 0 && colonIndex < lastLine.length - 1) {
      return lastLine.substring(colonIndex + 1).trim();
    }
    return lastLine.trim().isEmpty ? null : lastLine.trim();
  }

  String _stripHtml(String message) {
    return message.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  Map<String, dynamic> _unwrapMessageMap(Map<String, dynamic> payload) {
    final message = payload['message'];
    if (message is Map) {
      return Map<String, dynamic>.from(message);
    }
    return payload;
  }

  HostedAuthResult _parseHostedAuthResult(Map<String, dynamic> payload) {
    final message = _unwrapMessageMap(payload);
    final bootstrap = Map<String, dynamic>.from(
      (message['bootstrap'] as Map?) ?? const <String, dynamic>{},
    );
    final business = HostedBusinessProfile.fromJson(
      Map<String, dynamic>.from(
        (message['business'] as Map?) ?? const <String, dynamic>{},
      ),
    );
    final subscription = Map<String, dynamic>.from(
      (message['subscription'] as Map?) ?? const <String, dynamic>{},
    );
    _apiKey = '${message['api_key'] ?? ''}';
    _apiSecret = '${message['api_secret'] ?? ''}';
    return HostedAuthResult(
      sessionJson: <String, dynamic>{
        'username': '${message['username'] ?? ''}',
        'email': '${message['email'] ?? ''}',
        'api_key': _apiKey ?? '',
        'api_secret': _apiSecret ?? '',
        'hub_manager':
            '${message['hub_manager'] ?? message['email'] ?? message['username'] ?? ''}',
        'deployment_mode': 'neuradix_cloud',
        'plan_type': '${subscription['plan_type'] ?? business.planType}',
        'business_id': business.businessId,
        'business_name': business.businessName,
      },
      business: business,
      subscriptionPlanType: '${subscription['plan_type'] ?? business.planType}',
      subscriptionStatus:
          '${subscription['subscription_status'] ?? subscription['status'] ?? business.subscriptionStatus}',
      bootstrapJson: bootstrap,
    );
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedBase =
        baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;
    final uri = Uri.parse('$normalizedBase/$path');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: queryParameters);
  }
}

class _MethodCallOutcome {
  const _MethodCallOutcome({this.payload, this.error});

  final Map<String, dynamic>? payload;
  final Object? error;
}
