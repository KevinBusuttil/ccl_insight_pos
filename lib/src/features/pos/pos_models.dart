import 'dart:convert';

import '../bootstrap/bootstrap_config.dart';
import '../bootstrap/runtime_bench_url.dart';

class PosThemePalette {
  const PosThemePalette({
    this.menuCustomer = '#B86B32',
    this.menuSync = '#527B57',
    this.menuHistory = '#6266A5',
    this.menuProfile = '#5E7184',
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.textOnPrimary,
    required this.surface,
    required this.textAndCancelIcon,
    required this.shadowBorder,
    required this.hintText,
    required this.fontWhiteColor,
    required this.parkOrderButton,
    required this.active,
  });

  const PosThemePalette.fallback()
    : menuCustomer = '#B86B32',
      menuSync = '#527B57',
      menuHistory = '#6266A5',
      menuProfile = '#5E7184',
      primary = '#2B6F77',
      secondary = '#86A96F',
      accent = '#5E6B73',
      textOnPrimary = '#FFFFFF',
      surface = '#F4F7F5',
      textAndCancelIcon = '#000000',
      shadowBorder = '#C7C5C5',
      hintText = '#F3F2F5',
      fontWhiteColor = '#FFFFFF',
      parkOrderButton = '#355B66',
      active = '#F4F7F5';

  final String menuCustomer;
  final String menuSync;
  final String menuHistory;
  final String menuProfile;
  final String primary;
  final String secondary;
  final String accent;
  final String textOnPrimary;
  final String surface;
  final String textAndCancelIcon;
  final String shadowBorder;
  final String hintText;
  final String fontWhiteColor;
  final String parkOrderButton;
  final String active;

  factory PosThemePalette.fromJson(Map<String, dynamic> json) {
    const fallback = PosThemePalette.fallback();
    return PosThemePalette(
      menuCustomer: '${json['menu_customer'] ?? fallback.menuCustomer}',
      menuSync: '${json['menu_sync'] ?? fallback.menuSync}',
      menuHistory: '${json['menu_history'] ?? fallback.menuHistory}',
      menuProfile: '${json['menu_profile'] ?? fallback.menuProfile}',
      primary: '${json['primary'] ?? fallback.primary}',
      secondary: '${json['secondary'] ?? fallback.secondary}',
      accent: '${json['accent'] ?? json['asset'] ?? fallback.accent}',
      textOnPrimary:
          '${json['text_on_primary'] ?? json['font_white_color'] ?? fallback.textOnPrimary}',
      surface: '${json['surface'] ?? fallback.surface}',
      textAndCancelIcon:
          '${json['text_and_cancel_icon'] ?? fallback.textAndCancelIcon}',
      shadowBorder: '${json['shadow_border'] ?? fallback.shadowBorder}',
      hintText: '${json['hint_text'] ?? fallback.hintText}',
      fontWhiteColor:
          '${json['font_white_color'] ?? json['text_on_primary'] ?? fallback.fontWhiteColor}',
      parkOrderButton:
          '${json['park_order_button'] ?? json['active'] ?? fallback.parkOrderButton}',
      active: '${json['active_surface'] ?? json['surface'] ?? fallback.active}',
    );
  }

  Map<String, String> toJson() {
    return <String, String>{
      'menu_customer': menuCustomer,
      'menu_sync': menuSync,
      'menu_history': menuHistory,
      'menu_profile': menuProfile,
      'primary': primary,
      'secondary': secondary,
      'accent': accent,
      'text_on_primary': textOnPrimary,
      'surface': surface,
      'text_and_cancel_icon': textAndCancelIcon,
      'shadow_border': shadowBorder,
      'hint_text': hintText,
      'font_white_color': fontWhiteColor,
      'park_order_button': parkOrderButton,
      'active': active,
    };
  }
}

class PosBootstrapBundle {
  const PosBootstrapBundle({
    required this.brandName,
    required this.supportEmail,
    required this.appName,
    required this.deploymentMode,
    required this.planType,
    required this.defaultCloudBaseUrl,
    required this.priceList,
    required this.offlineHistoryDays,
    required this.offlineSyncCustomerLimit,
    required this.minimumOrderAmount,
    required this.currencySymbol,
    required this.notesBypassMinimum,
    required this.theme,
    required this.features,
    this.planCaps = const <String, Object?>{},
    this.syncMode = 'dedicated_backend',
    this.relayUrl = '',
    this.protocolVersion = 1,
    this.metadataOnly = false,
  });

  final String brandName;
  final String supportEmail;
  final String appName;
  final String deploymentMode;
  final String planType;
  final String defaultCloudBaseUrl;
  final String priceList;
  final int offlineHistoryDays;
  final int offlineSyncCustomerLimit;
  final double minimumOrderAmount;
  final String currencySymbol;
  final bool notesBypassMinimum;
  final PosThemePalette theme;
  final Map<String, bool> features;
  final Map<String, Object?> planCaps;
  final String syncMode;
  final String relayUrl;
  final int protocolVersion;
  final bool metadataOnly;

  factory PosBootstrapBundle.fromResponses(
    Map<String, dynamic> platformJson,
    Map<String, dynamic> clientJson,
  ) {
    final featuresJson = Map<String, dynamic>.from(
      (platformJson['features'] as Map?) ?? const <String, dynamic>{},
    );
    final deploymentMode =
        '${platformJson['deployment_mode'] ?? 'external_backend'}';
    final planType = '${platformJson['plan_type'] ?? 'free_local'}';
    final fallbackSyncMode =
        deploymentMode == 'neuradix_cloud'
            ? (planType == 'free_cloud' || planType == 'paid_cloud'
                ? 'hosted_backend'
                : 'device_local')
            : 'dedicated_backend';
    return PosBootstrapBundle(
      brandName:
          '${platformJson['brand_name'] ?? clientJson['brand_name'] ?? 'Neuradix POS'}',
      supportEmail:
          '${clientJson['support_email'] ?? platformJson['support_email'] ?? ''}',
      appName: '${platformJson['app_name'] ?? 'neuradix-pos'}',
      deploymentMode: deploymentMode,
      planType: planType,
      syncMode: '${platformJson['sync_mode'] ?? fallbackSyncMode}',
      relayUrl: '${platformJson['relay_url'] ?? ''}',
      protocolVersion:
          int.tryParse('${platformJson['protocol_version'] ?? 1}') ?? 1,
      metadataOnly:
          platformJson['metadata_only'] == true ||
          platformJson['metadata_only'] == 1 ||
          platformJson['metadata_only'] == '1',
      defaultCloudBaseUrl: normalizeBenchUrlForRuntime(
        '${platformJson['default_cloud_base_url'] ?? 'http://neuradix-cloud.localhost:8018'}',
      ),
      priceList: '${platformJson['price_list'] ?? 'Standard Selling'}',
      offlineHistoryDays:
          int.tryParse('${platformJson['offline_history_days'] ?? 14}') ?? 14,
      offlineSyncCustomerLimit:
          int.tryParse(
            '${platformJson['offline_sync_customer_limit'] ?? 10}',
          ) ??
          10,
      minimumOrderAmount:
          double.tryParse(
            '${clientJson['minimum_order_amount'] ?? platformJson['minimum_order_amount'] ?? 50}',
          ) ??
          50,
      currencySymbol: '${platformJson['currency_symbol'] ?? 'EUR'}',
      notesBypassMinimum:
          '${clientJson['notes_bypass_minimum'] ?? platformJson['notes_bypass_minimum'] ?? true}' ==
              'true' ||
          '${clientJson['notes_bypass_minimum'] ?? platformJson['notes_bypass_minimum'] ?? 1}' ==
              '1',
      theme: PosThemePalette.fromJson(
        Map<String, dynamic>.from(
          (platformJson['theme'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      features: featuresJson.map(
        (Object? key, dynamic value) =>
            MapEntry('$key', value == true || value == 1 || value == '1'),
      ),
      planCaps: Map<String, Object?>.from(
        ((platformJson['plan_caps'] as Map?) ?? const <String, dynamic>{}).map(
          (Object? key, dynamic value) => MapEntry('$key', value),
        ),
      ),
    );
  }

  factory PosBootstrapBundle.fromPlatform(Map<String, dynamic> platformJson) {
    return PosBootstrapBundle.fromResponses(platformJson, <String, dynamic>{});
  }
}

class PosLoginSession {
  const PosLoginSession({
    required this.username,
    required this.email,
    required this.apiKey,
    required this.apiSecret,
    required this.hubManager,
    this.deploymentMode = 'external_backend',
    this.planType = 'free_local',
    this.businessId = '',
    this.businessName = '',
    this.previewMode = false,
  });

  final String username;
  final String email;
  final String apiKey;
  final String apiSecret;
  final String hubManager;
  final String deploymentMode;
  final String planType;
  final String businessId;
  final String businessName;
  final bool previewMode;

  factory PosLoginSession.fromJson(Map<String, dynamic> json) {
    final deploymentMode = '${json['deployment_mode'] ?? 'external_backend'}';
    final username = '${json['username'] ?? ''}';
    final email = '${json['email'] ?? ''}';
    final rawHubManager = '${json['hub_manager'] ?? ''}';
    final hubManager =
        deploymentMode == 'external_backend'
            ? (email.isNotEmpty
                ? email
                : (rawHubManager.isNotEmpty ? rawHubManager : username))
            : (rawHubManager.isNotEmpty
                ? rawHubManager
                : (email.isNotEmpty ? email : username));
    return PosLoginSession(
      username: username,
      email: email,
      apiKey: '${json['api_key'] ?? ''}',
      apiSecret: '${json['api_secret'] ?? ''}',
      hubManager: hubManager,
      deploymentMode: deploymentMode,
      planType: '${json['plan_type'] ?? 'free_local'}',
      businessId: '${json['business_id'] ?? ''}',
      businessName: '${json['business_name'] ?? ''}',
      previewMode: json['preview_mode'] == true,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'username': username,
      'email': email,
      'api_key': apiKey,
      'api_secret': apiSecret,
      'hub_manager': hubManager,
      'deployment_mode': deploymentMode,
      'plan_type': planType,
      'business_id': businessId,
      'business_name': businessName,
      'preview_mode': previewMode,
    };
  }
}

class PosCustomer {
  const PosCustomer({
    required this.id,
    required this.displayName,
    required this.mobileNo,
    required this.email,
    required this.customerCode,
    required this.creditLimit,
    required this.outstandingAmount,
    required this.isFrozen,
    required this.primaryAddress,
    required this.paymentTerm,
  });

  final String id;
  final String displayName;
  final String mobileNo;
  final String email;
  final String customerCode;
  final double creditLimit;
  final double outstandingAmount;
  final bool isFrozen;
  final String primaryAddress;
  final String paymentTerm;

  factory PosCustomer.fromApi(Map<String, dynamic> json) {
    return PosCustomer(
      id: '${json['name'] ?? ''}',
      displayName: '${json['customer_name'] ?? json['name'] ?? ''}',
      mobileNo: '${json['mobile_no'] ?? ''}',
      email: '${json['email_id'] ?? ''}',
      customerCode: '${json['custom_customer_id'] ?? ''}',
      creditLimit:
          double.tryParse('${json['custom_customer_credit_limit'] ?? 0}') ?? 0,
      outstandingAmount:
          double.tryParse('${json['custom_customer_outstanding'] ?? 0}') ?? 0,
      isFrozen:
          json['custom_frozen_customer'] == true ||
          json['custom_frozen_customer'] == 1 ||
          json['custom_frozen_customer'] == '1',
      primaryAddress: '${json['primary_address'] ?? ''}',
      paymentTerm: '${json['custom_payment_term'] ?? ''}',
    );
  }

  factory PosCustomer.fromRow(Map<String, Object?> row) {
    final payload = Map<String, dynamic>.from(
      jsonDecode('${row['payload_json']}') as Map,
    );
    return PosCustomer.fromApi(payload);
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'customer_id': id,
      'display_name': displayName,
      'mobile_no': mobileNo,
      'payload_json': jsonEncode(<String, Object?>{
        'name': id,
        'customer_name': displayName,
        'mobile_no': mobileNo,
        'email_id': email,
        'custom_customer_id': customerCode,
        'custom_customer_credit_limit': creditLimit,
        'custom_customer_outstanding': outstandingAmount,
        'custom_frozen_customer': isFrozen ? 1 : 0,
        'primary_address': primaryAddress,
        'custom_payment_term': paymentTerm,
      }),
    };
  }
}

class PosCatalogItem {
  const PosCatalogItem({
    required this.itemCode,
    required this.groupName,
    required this.displayName,
    required this.imageUrl,
    this.imageVersion = '',
    this.localImagePath = '',
    this.defaultUom = 'Unit',
    this.pricingAvailable = true,
    required this.price,
    required this.stockQty,
    required this.taxRows,
    required this.comboItems,
    required this.attributeGroups,
  });

  final String itemCode;
  final String groupName;
  final String displayName;
  final String imageUrl;
  final String imageVersion;
  final String localImagePath;
  final String defaultUom;
  final bool pricingAvailable;
  final double price;
  final double stockQty;
  final List<Map<String, dynamic>> taxRows;
  final List<Map<String, dynamic>> comboItems;
  final List<Map<String, dynamic>> attributeGroups;

  factory PosCatalogItem.fromApi(String groupName, Map<String, dynamic> json) {
    return PosCatalogItem(
      itemCode: '${json['item_code'] ?? ''}',
      groupName: groupName,
      displayName: '${json['item_name'] ?? json['item_code'] ?? ''}',
      imageUrl: '${json['image'] ?? ''}',
      imageVersion: '${json['image_version'] ?? ''}',
      localImagePath: '${json['local_image_path'] ?? ''}',
      defaultUom: '${json['default_uom'] ?? 'Unit'}',
      pricingAvailable: json['pricing_available'] != false,
      price: double.tryParse('${json['product_price'] ?? 0}') ?? 0,
      stockQty: double.tryParse('${json['stock_qty'] ?? 0}') ?? 0,
      taxRows: ((json['tax'] as List?) ?? const <dynamic>[])
          .map((dynamic row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false),
      comboItems: ((json['combo_items'] as List?) ?? const <dynamic>[])
          .map((dynamic row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false),
      attributeGroups: ((json['attributes'] as List?) ?? const <dynamic>[])
          .map((dynamic row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false),
    );
  }

  factory PosCatalogItem.fromRow(Map<String, Object?> row, String groupName) {
    final payload = Map<String, dynamic>.from(
      jsonDecode('${row['pricing_snapshot_json']}') as Map,
    );
    payload['image'] = row['image_url'] ?? payload['image'];
    payload['image_version'] = row['image_version'] ?? payload['image_version'];
    payload['local_image_path'] =
        row['local_image_path'] ?? payload['local_image_path'];
    payload['product_price'] = row['price'] ?? payload['product_price'];
    payload['stock_qty'] = row['stock_qty'] ?? payload['stock_qty'];
    return PosCatalogItem.fromApi(groupName, payload);
  }

  Map<String, Object?> toRow(String categoryId) {
    return <String, Object?>{
      'item_id': itemCode,
      'category_id': categoryId,
      'display_name': displayName,
      'image_url': imageUrl,
      'image_version': imageVersion,
      'local_image_path': localImagePath,
      'price': price,
      'stock_qty': stockQty,
      'pricing_snapshot_json': jsonEncode(<String, Object?>{
        'item_code': itemCode,
        'item_name': displayName,
        'image': imageUrl,
        'image_version': imageVersion,
        'local_image_path': localImagePath,
        'product_price': price,
        'default_uom': defaultUom,
        'pricing_available': pricingAvailable,
        'stock_qty': stockQty,
        'tax': taxRows,
        'combo_items': comboItems,
        'attributes': attributeGroups,
      }),
    };
  }

  PosCatalogItem copyWith({
    String? imageUrl,
    String? imageVersion,
    String? localImagePath,
    double? price,
    double? stockQty,
  }) {
    return PosCatalogItem(
      itemCode: itemCode,
      groupName: groupName,
      displayName: displayName,
      imageUrl: imageUrl ?? this.imageUrl,
      imageVersion: imageVersion ?? this.imageVersion,
      localImagePath: localImagePath ?? this.localImagePath,
      defaultUom: defaultUom,
      pricingAvailable: pricingAvailable,
      price: price ?? this.price,
      stockQty: stockQty ?? this.stockQty,
      taxRows: taxRows,
      comboItems: comboItems,
      attributeGroups: attributeGroups,
    );
  }
}

class PosCatalogGroup {
  const PosCatalogGroup({
    required this.groupName,
    required this.items,
    this.groupImageUrl = '',
  });

  final String groupName;
  final List<PosCatalogItem> items;
  final String groupImageUrl;

  factory PosCatalogGroup.fromApi(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List?) ?? const <dynamic>[];
    final groupName = '${json['item_group'] ?? ''}';
    return PosCatalogGroup(
      groupName: groupName,
      groupImageUrl: '${json['item_group_image'] ?? ''}',
      items: itemsJson
          .map(
            (dynamic item) => PosCatalogItem.fromApi(
              groupName,
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  PosCatalogGroup copyWith({
    List<PosCatalogItem>? items,
    String? groupImageUrl,
  }) {
    return PosCatalogGroup(
      groupName: groupName,
      items: items ?? this.items,
      groupImageUrl: groupImageUrl ?? this.groupImageUrl,
    );
  }
}

class PosHistoryOrderLine {
  const PosHistoryOrderLine({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.rate,
    required this.notes,
    required this.taxRows,
    required this.subItems,
  });

  final String itemCode;
  final String itemName;
  final double qty;
  final double rate;
  final String notes;
  final List<Map<String, dynamic>> taxRows;
  final List<Map<String, dynamic>> subItems;

  factory PosHistoryOrderLine.fromJson(Map<String, dynamic> json) {
    return PosHistoryOrderLine(
      itemCode: '${json['item_code'] ?? ''}',
      itemName: '${json['item_name'] ?? json['item_code'] ?? ''}',
      qty: double.tryParse('${json['qty'] ?? 0}') ?? 0,
      rate: double.tryParse('${json['rate'] ?? 0}') ?? 0,
      notes: '${json['notes'] ?? ''}',
      taxRows: ((json['tax'] as List?) ?? const <dynamic>[])
          .map((dynamic row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false),
      subItems: ((json['sub_items'] as List?) ?? const <dynamic>[])
          .map((dynamic row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'item_code': itemCode,
      'item_name': itemName,
      'qty': qty,
      'rate': rate,
      'notes': notes,
      'tax': taxRows,
      'sub_items': subItems,
    };
  }
}

class PosHistoryOrder {
  const PosHistoryOrder({
    required this.id,
    required this.customer,
    required this.transactionDate,
    required this.grandTotal,
    required this.status,
    required this.isParked,
    required this.isLocalOnly,
    required this.items,
  });

  final String id;
  final String customer;
  final String transactionDate;
  final double grandTotal;
  final String status;
  final bool isParked;
  final bool isLocalOnly;
  final List<PosHistoryOrderLine> items;

  factory PosHistoryOrder.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List?) ?? const <dynamic>[];
    return PosHistoryOrder(
      id: '${json['name'] ?? json['id'] ?? ''}',
      customer: '${json['customer'] ?? ''}',
      transactionDate:
          '${json['transaction_date'] ?? json['updated_at'] ?? ''}',
      grandTotal: double.tryParse('${json['grand_total'] ?? 0}') ?? 0,
      status: '${json['status'] ?? 'Draft'}',
      isParked:
          json['custom_is_parked'] == true ||
          json['custom_is_parked'] == 1 ||
          json['custom_is_parked'] == '1' ||
          json['is_parked'] == true,
      isLocalOnly: json['is_local_only'] == true,
      items: itemsJson
          .map(
            (dynamic item) => PosHistoryOrderLine.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': id,
      'customer': customer,
      'transaction_date': transactionDate,
      'grand_total': grandTotal,
      'status': status,
      'custom_is_parked': isParked,
      'is_local_only': isLocalOnly,
      'items': items.map((PosHistoryOrderLine item) => item.toJson()).toList(),
    };
  }
}

class PosAccountSummary {
  const PosAccountSummary({
    required this.hubManager,
    required this.fullName,
    required this.email,
    required this.mobileNo,
    required this.imageUrl,
    required this.currencySymbol,
    required this.balance,
    required this.series,
    required this.submittedOrdersToday,
    required this.lastOrderDate,
    required this.lastTransactionDate,
  });

  final String hubManager;
  final String fullName;
  final String email;
  final String mobileNo;
  final String imageUrl;
  final String currencySymbol;
  final double balance;
  final String series;
  final int submittedOrdersToday;
  final String lastOrderDate;
  final String lastTransactionDate;

  factory PosAccountSummary.fromJson(Map<String, dynamic> json) {
    return PosAccountSummary(
      hubManager: '${json['hub_manager'] ?? ''}',
      fullName: '${json['full_name'] ?? ''}',
      email: '${json['email'] ?? ''}',
      mobileNo: '${json['mobile_no'] ?? ''}',
      imageUrl: '${json['image_url'] ?? json['image'] ?? ''}',
      currencySymbol: '${json['currency_symbol'] ?? 'EUR'}',
      balance: double.tryParse('${json['balance'] ?? 0}') ?? 0,
      series: '${json['series'] ?? ''}',
      submittedOrdersToday:
          int.tryParse('${json['submitted_orders_today'] ?? 0}') ?? 0,
      lastOrderDate: '${json['last_order_date'] ?? ''}',
      lastTransactionDate: '${json['last_transaction_date'] ?? ''}',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hub_manager': hubManager,
      'full_name': fullName,
      'email': email,
      'mobile_no': mobileNo,
      'image_url': imageUrl,
      'currency_symbol': currencySymbol,
      'balance': balance,
      'series': series,
      'submitted_orders_today': submittedOrdersToday,
      'last_order_date': lastOrderDate,
      'last_transaction_date': lastTransactionDate,
    };
  }
}

class PosCustomerPolicy {
  const PosCustomerPolicy({
    required this.customer,
    required this.customerCode,
    required this.isFrozen,
    required this.minimumOrderAmount,
    required this.minimumOrderRequired,
    required this.notesBypassMinimum,
    required this.outstandingAmount,
    required this.hasOutstandingDocuments,
    required this.sameDayOrders,
  });

  final String customer;
  final String customerCode;
  final bool isFrozen;
  final double minimumOrderAmount;
  final bool minimumOrderRequired;
  final bool notesBypassMinimum;
  final double outstandingAmount;
  final bool hasOutstandingDocuments;
  final int sameDayOrders;

  factory PosCustomerPolicy.fromJson(Map<String, dynamic> json) {
    return PosCustomerPolicy(
      customer: '${json['customer'] ?? ''}',
      customerCode: '${json['custom_customer_id'] ?? ''}',
      isFrozen:
          json['is_frozen'] == true ||
          json['is_frozen'] == 1 ||
          json['is_frozen'] == '1',
      minimumOrderAmount:
          double.tryParse('${json['minimum_order_amount'] ?? 0}') ?? 0,
      minimumOrderRequired:
          json['minimum_order_required'] == true ||
          json['minimum_order_required'] == 1 ||
          json['minimum_order_required'] == '1',
      notesBypassMinimum:
          json['notes_bypass_minimum'] == true ||
          json['notes_bypass_minimum'] == 1 ||
          json['notes_bypass_minimum'] == '1',
      outstandingAmount:
          double.tryParse('${json['outstanding_amount'] ?? 0}') ?? 0,
      hasOutstandingDocuments:
          json['has_outstanding_documents'] == true ||
          json['has_outstanding_documents'] == 1 ||
          json['has_outstanding_documents'] == '1',
      sameDayOrders: int.tryParse('${json['same_day_orders'] ?? 0}') ?? 0,
    );
  }
}

class CartLine {
  const CartLine({
    required this.itemCode,
    required this.groupName,
    required this.displayName,
    required this.price,
    required this.qty,
    this.notes = '',
    this.uom = 'Unit',
    this.taxRows = const <Map<String, dynamic>>[],
  });

  final String itemCode;
  final String groupName;
  final String displayName;
  final double price;
  final int qty;
  final String notes;
  final String uom;
  final List<Map<String, dynamic>> taxRows;

  double get total => price * qty;

  CartLine copyWith({
    String? itemCode,
    String? groupName,
    String? displayName,
    double? price,
    int? qty,
    String? notes,
    List<Map<String, dynamic>>? taxRows,
  }) {
    return CartLine(
      itemCode: itemCode ?? this.itemCode,
      groupName: groupName ?? this.groupName,
      displayName: displayName ?? this.displayName,
      price: price ?? this.price,
      qty: qty ?? this.qty,
      notes: notes ?? this.notes,
      uom: uom,
      taxRows: taxRows ?? this.taxRows,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'item_code': itemCode,
      'item_name': displayName,
      'group_name': groupName,
      'rate': price,
      'qty': qty,
      'uom': uom,
      'notes': notes,
      'tax': taxRows,
    };
  }
}

class PosIssueStatement {
  const PosIssueStatement({
    required this.customerId,
    required this.balance,
    required this.paymentTerm,
    required this.vat,
    required this.primaryAddress,
    required this.minimumOrderRequired,
    required this.rows,
  });

  final String customerId;
  final double balance;
  final String paymentTerm;
  final String vat;
  final String primaryAddress;
  final bool minimumOrderRequired;
  final List<PosIssueStatementRow> rows;

  factory PosIssueStatement.fromJson(Map<String, dynamic> json) {
    final custTrans = Map<String, dynamic>.from(
      (json['CustTrans'] as Map?) ?? const <String, dynamic>{},
    );
    final rowsJson =
        (custTrans['BTLAPICustTrans'] as List?) ?? const <dynamic>[];
    return PosIssueStatement(
      customerId: '${json['CustomerId'] ?? ''}',
      balance: double.tryParse('${json['Balance'] ?? 0}') ?? 0,
      paymentTerm: '${json['payment_term'] ?? ''}',
      vat: '${json['vat'] ?? ''}',
      primaryAddress: '${json['primary_address'] ?? ''}',
      minimumOrderRequired:
          json['min_order_limit'] == true ||
          json['min_order_limit'] == 1 ||
          json['min_order_limit'] == '1',
      rows: rowsJson
          .map(
            (dynamic row) => PosIssueStatementRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class PosIssueStatementRow {
  const PosIssueStatementRow({
    required this.invoiceId,
    required this.invoiceDate,
    required this.dueDate,
    required this.amount,
    required this.balance,
    required this.totalRowBalance,
    required this.currency,
    required this.transactionType,
  });

  final String invoiceId;
  final String invoiceDate;
  final String dueDate;
  final double amount;
  final double balance;
  final double totalRowBalance;
  final String currency;
  final String transactionType;

  factory PosIssueStatementRow.fromJson(Map<String, dynamic> json) {
    return PosIssueStatementRow(
      invoiceId: '${json['InvoiceId'] ?? ''}',
      invoiceDate: '${json['InvoiceDate'] ?? ''}',
      dueDate: '${json['DueDate'] ?? ''}',
      amount: double.tryParse('${json['Amount'] ?? 0}') ?? 0,
      balance: double.tryParse('${json['Balance'] ?? 0}') ?? 0,
      totalRowBalance:
          double.tryParse('${json['Total Row Balance'] ?? 0}') ?? 0,
      currency: '${json['Currency'] ?? ''}',
      transactionType: '${json['TransType'] ?? ''}',
    );
  }
}

class PosVisitPlanEntry {
  const PosVisitPlanEntry({
    required this.id,
    required this.salesRep,
    required this.customerId,
    required this.customerName,
    required this.customerCode,
    required this.visitDate,
    required this.sequenceNo,
    required this.status,
    required this.notes,
    required this.startsOn,
    required this.endsOn,
    required this.modified,
  });

  final String id;
  final String salesRep;
  final String customerId;
  final String customerName;
  final String customerCode;
  final String visitDate;
  final int sequenceNo;
  final String status;
  final String notes;
  final String startsOn;
  final String endsOn;
  final String modified;

  factory PosVisitPlanEntry.fromJson(Map<String, dynamic> json) {
    return PosVisitPlanEntry(
      id: '${json['name'] ?? json['id'] ?? ''}',
      salesRep: '${json['sales_rep'] ?? ''}',
      customerId: '${json['customer'] ?? ''}',
      customerName: '${json['customer_name'] ?? json['customer'] ?? ''}',
      customerCode:
          '${json['customer_code'] ?? json['custom_customer_id'] ?? ''}',
      visitDate: '${json['visit_date'] ?? ''}',
      sequenceNo: int.tryParse('${json['sequence_no'] ?? 0}') ?? 0,
      status: '${json['status'] ?? 'Planned'}',
      notes: '${json['notes'] ?? ''}',
      startsOn: '${json['starts_on'] ?? ''}',
      endsOn: '${json['ends_on'] ?? ''}',
      modified: '${json['modified'] ?? ''}',
    );
  }

  factory PosVisitPlanEntry.fromRow(Map<String, Object?> row) {
    return PosVisitPlanEntry.fromJson(
      Map<String, dynamic>.from(jsonDecode('${row['payload_json']}') as Map),
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'entry_id': id,
      'visit_date': visitDate,
      'sales_rep': salesRep,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_code': customerCode,
      'sequence_no': sequenceNo,
      'status': status,
      'notes': notes,
      'starts_on': startsOn,
      'ends_on': endsOn,
      'payload_json': jsonEncode(toJson()),
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': id,
      'sales_rep': salesRep,
      'customer': customerId,
      'customer_name': customerName,
      'customer_code': customerCode,
      'visit_date': visitDate,
      'sequence_no': sequenceNo,
      'status': status,
      'notes': notes,
      'starts_on': startsOn,
      'ends_on': endsOn,
      'modified': modified,
    };
  }
}

class PosCustomerPriceSnapshot {
  const PosCustomerPriceSnapshot({
    required this.syncDate,
    required this.customerId,
    required this.customerCode,
    required this.itemCode,
    required this.price,
  });

  final String syncDate;
  final String customerId;
  final String customerCode;
  final String itemCode;
  final double price;

  factory PosCustomerPriceSnapshot.fromJson(
    String syncDate,
    Map<String, dynamic> json,
  ) {
    return PosCustomerPriceSnapshot(
      syncDate: syncDate,
      customerId: '${json['customer'] ?? ''}',
      customerCode: '${json['custom_customer_id'] ?? ''}',
      itemCode: '${json['item_code'] ?? ''}',
      price: double.tryParse('${json['price'] ?? 0}') ?? 0,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'sync_date': syncDate,
      'customer_id': customerId,
      'item_code': itemCode,
      'price': price,
      'payload_json': jsonEncode(<String, Object?>{
        'customer': customerId,
        'custom_customer_id': customerCode,
        'item_code': itemCode,
        'price': price,
      }),
    };
  }
}

class PosImageManifestEntry {
  const PosImageManifestEntry({
    required this.itemCode,
    required this.imageUrl,
    required this.imageVersion,
    this.localPath = '',
  });

  final String itemCode;
  final String imageUrl;
  final String imageVersion;
  final String localPath;

  factory PosImageManifestEntry.fromJson(Map<String, dynamic> json) {
    return PosImageManifestEntry(
      itemCode: '${json['item_code'] ?? ''}',
      imageUrl: '${json['image_url'] ?? json['image'] ?? ''}',
      imageVersion: '${json['image_version'] ?? ''}',
      localPath: '${json['local_path'] ?? ''}',
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'item_id': itemCode,
      'image_url': imageUrl,
      'image_version': imageVersion,
      'local_path': localPath,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class PosOfflineDaySyncPack {
  const PosOfflineDaySyncPack({
    required this.salesRep,
    required this.syncDate,
    required this.weekStart,
    required this.syncCustomerLimit,
    required this.planEntries,
    required this.customerDirectory,
    required this.catalogGroups,
    required this.customerPriceRows,
    required this.customerPolicies,
    required this.imageManifest,
    required this.syncCursors,
  });

  final String salesRep;
  final String syncDate;
  final String weekStart;
  final int syncCustomerLimit;
  final List<PosVisitPlanEntry> planEntries;
  final List<PosCustomer> customerDirectory;
  final List<PosCatalogGroup> catalogGroups;
  final List<PosCustomerPriceSnapshot> customerPriceRows;
  final List<PosCustomerPolicy> customerPolicies;
  final List<PosImageManifestEntry> imageManifest;
  final Map<String, String> syncCursors;

  factory PosOfflineDaySyncPack.fromJson(Map<String, dynamic> json) {
    final syncDate = '${json['sync_date'] ?? ''}';
    return PosOfflineDaySyncPack(
      salesRep: '${json['sales_rep'] ?? ''}',
      syncDate: syncDate,
      weekStart: '${json['week_start'] ?? ''}',
      syncCustomerLimit:
          int.tryParse('${json['sync_customer_limit'] ?? 10}') ?? 10,
      planEntries: ((json['plan_entries'] as List?) ?? const <dynamic>[])
          .map(
            (dynamic row) => PosVisitPlanEntry.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
      customerDirectory: ((json['customer_directory'] as List?) ??
              const <dynamic>[])
          .map(
            (dynamic row) =>
                PosCustomer.fromApi(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      catalogGroups: ((json['catalog_groups'] as List?) ?? const <dynamic>[])
          .map(
            (dynamic row) =>
                PosCatalogGroup.fromApi(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      customerPriceRows: ((json['customer_price_rows'] as List?) ??
              const <dynamic>[])
          .map(
            (dynamic row) => PosCustomerPriceSnapshot.fromJson(
              syncDate,
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
      customerPolicies: ((json['customer_policy_rows'] as List?) ??
              const <dynamic>[])
          .map(
            (dynamic row) => PosCustomerPolicy.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
      imageManifest: ((json['image_manifest'] as List?) ?? const <dynamic>[])
          .map(
            (dynamic row) => PosImageManifestEntry.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
      syncCursors: Map<String, String>.from(
        ((json['sync_cursors'] as Map?) ?? const <String, dynamic>{}).map(
          (Object? key, dynamic value) => MapEntry('$key', '$value'),
        ),
      ),
    );
  }
}

class PosPreviewData {
  static const PosThemePalette theme = PosThemePalette.fallback();

  static const PosBootstrapBundle bootstrap = PosBootstrapBundle(
    brandName: 'CassarCamilleri POS',
    supportEmail: 'support@neuradix.local',
    appName: 'neuradix-pos',
    deploymentMode: 'external_backend',
    planType: 'free_local',
    defaultCloudBaseUrl: neuradixDefaultCloudBaseUrlFallback,
    priceList: 'Standard Selling',
    offlineHistoryDays: 14,
    offlineSyncCustomerLimit: 10,
    minimumOrderAmount: 50,
    currencySymbol: 'EUR',
    notesBypassMinimum: true,
    theme: theme,
    features: <String, bool>{
      'customer_create': true,
      'parked_orders': true,
      'offline_sync': true,
      'issue_statements': true,
      'insight_pricing': true,
    },
    planCaps: <String, Object?>{
      'plan_type': 'external_backend',
      'sync_enabled': true,
    },
  );

  static const PosLoginSession session = PosLoginSession(
    username: 'preview',
    email: 'preview@neuradix.local',
    apiKey: '',
    apiSecret: '',
    hubManager: 'preview',
    deploymentMode: 'external_backend',
    previewMode: true,
  );

  static const List<PosCustomer> customers = <PosCustomer>[
    PosCustomer(
      id: 'CUST-001',
      displayName: 'Cassar Retail Valletta',
      mobileNo: '99880011',
      email: 'valletta@cassar.example',
      customerCode: 'AX-1001',
      creditLimit: 500,
      outstandingAmount: 0,
      isFrozen: false,
      primaryAddress: 'Valletta, Malta',
      paymentTerm: '30 Days',
    ),
    PosCustomer(
      id: 'CUST-002',
      displayName: 'Camilleri Express Sliema',
      mobileNo: '99880022',
      email: 'sliema@cassar.example',
      customerCode: 'AX-1002',
      creditLimit: 700,
      outstandingAmount: 145.30,
      isFrozen: false,
      primaryAddress: 'Sliema, Malta',
      paymentTerm: 'Immediate',
    ),
    PosCustomer(
      id: 'CUST-003',
      displayName: 'Harbour Kiosk',
      mobileNo: '99880033',
      email: 'harbour@cassar.example',
      customerCode: 'AX-1003',
      creditLimit: 200,
      outstandingAmount: 0,
      isFrozen: true,
      primaryAddress: 'Harbour, Malta',
      paymentTerm: 'Cash',
    ),
  ];

  static const List<PosCatalogGroup> catalog = <PosCatalogGroup>[
    PosCatalogGroup(
      groupName: 'Coffee',
      items: <PosCatalogItem>[
        PosCatalogItem(
          itemCode: 'COFFEE-001',
          groupName: 'Coffee',
          displayName: 'Classic Blend Beans',
          imageUrl: '',
          price: 11.50,
          stockQty: 18,
          taxRows: <Map<String, dynamic>>[],
          comboItems: <Map<String, dynamic>>[],
          attributeGroups: <Map<String, dynamic>>[],
        ),
        PosCatalogItem(
          itemCode: 'COFFEE-002',
          groupName: 'Coffee',
          displayName: 'Espresso Roast',
          imageUrl: '',
          price: 13.90,
          stockQty: 12,
          taxRows: <Map<String, dynamic>>[],
          comboItems: <Map<String, dynamic>>[],
          attributeGroups: <Map<String, dynamic>>[],
        ),
      ],
    ),
    PosCatalogGroup(
      groupName: 'Pastry',
      items: <PosCatalogItem>[
        PosCatalogItem(
          itemCode: 'PASTRY-001',
          groupName: 'Pastry',
          displayName: 'Butter Croissant',
          imageUrl: '',
          price: 2.30,
          stockQty: 44,
          taxRows: <Map<String, dynamic>>[],
          comboItems: <Map<String, dynamic>>[],
          attributeGroups: <Map<String, dynamic>>[],
        ),
        PosCatalogItem(
          itemCode: 'PASTRY-002',
          groupName: 'Pastry',
          displayName: 'Almond Danish',
          imageUrl: '',
          price: 3.10,
          stockQty: 22,
          taxRows: <Map<String, dynamic>>[],
          comboItems: <Map<String, dynamic>>[],
          attributeGroups: <Map<String, dynamic>>[],
        ),
      ],
    ),
    PosCatalogGroup(
      groupName: 'Tea',
      items: <PosCatalogItem>[
        PosCatalogItem(
          itemCode: 'TEA-001',
          groupName: 'Tea',
          displayName: 'English Breakfast',
          imageUrl: '',
          price: 4.20,
          stockQty: 30,
          taxRows: <Map<String, dynamic>>[],
          comboItems: <Map<String, dynamic>>[],
          attributeGroups: <Map<String, dynamic>>[],
        ),
      ],
    ),
  ];

  static const List<PosHistoryOrder> history = <PosHistoryOrder>[
    PosHistoryOrder(
      id: 'SO-00045',
      customer: 'Cassar Retail Valletta',
      transactionDate: '2026-06-09',
      grandTotal: 56.80,
      status: 'Submitted',
      isParked: false,
      isLocalOnly: false,
      items: <PosHistoryOrderLine>[
        PosHistoryOrderLine(
          itemCode: 'COFFEE-001',
          itemName: 'Classic Blend Beans',
          qty: 2,
          rate: 11.50,
          notes: '',
          taxRows: <Map<String, dynamic>>[],
          subItems: <Map<String, dynamic>>[],
        ),
        PosHistoryOrderLine(
          itemCode: 'PASTRY-001',
          itemName: 'Butter Croissant',
          qty: 6,
          rate: 2.30,
          notes: '',
          taxRows: <Map<String, dynamic>>[],
          subItems: <Map<String, dynamic>>[],
        ),
      ],
    ),
  ];

  static const PosAccountSummary account = PosAccountSummary(
    hubManager: 'preview',
    fullName: 'Preview Operator',
    email: 'preview@neuradix.local',
    mobileNo: '99990000',
    imageUrl: '',
    currencySymbol: 'EUR',
    balance: 245.80,
    series: 'SO-',
    submittedOrdersToday: 4,
    lastOrderDate: '2026-06-09',
    lastTransactionDate: '2026-06-09',
  );

  static const Map<String, PosCustomerPolicy> policyByCustomer =
      <String, PosCustomerPolicy>{
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
        'CUST-002': PosCustomerPolicy(
          customer: 'CUST-002',
          customerCode: 'AX-1002',
          isFrozen: false,
          minimumOrderAmount: 50,
          minimumOrderRequired: true,
          notesBypassMinimum: true,
          outstandingAmount: 145.30,
          hasOutstandingDocuments: true,
          sameDayOrders: 0,
        ),
        'CUST-003': PosCustomerPolicy(
          customer: 'CUST-003',
          customerCode: 'AX-1003',
          isFrozen: true,
          minimumOrderAmount: 50,
          minimumOrderRequired: true,
          notesBypassMinimum: true,
          outstandingAmount: 0,
          hasOutstandingDocuments: false,
          sameDayOrders: 0,
        ),
      };
}
