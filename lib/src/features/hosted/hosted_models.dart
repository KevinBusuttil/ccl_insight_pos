import 'dart:convert';

class HostedBusinessProfile {
  const HostedBusinessProfile({
    required this.businessId,
    required this.businessName,
    required this.slug,
    required this.ownerUser,
    required this.membershipRole,
    required this.planType,
    required this.subscriptionStatus,
    required this.deploymentMode,
    this.planCaps = const <String, Object?>{},
    this.features = const <String, bool>{},
  });

  final String businessId;
  final String businessName;
  final String slug;
  final String ownerUser;
  final String membershipRole;
  final String planType;
  final String subscriptionStatus;
  final String deploymentMode;
  final Map<String, Object?> planCaps;
  final Map<String, bool> features;

  factory HostedBusinessProfile.fromJson(Map<String, dynamic> json) {
    final businessValue = json['business'];
    final businessJson =
        businessValue is Map ? Map<String, dynamic>.from(businessValue) : json;
    return HostedBusinessProfile(
      businessId:
          '${businessJson['business'] ?? businessJson['name'] ?? businessValue ?? ''}',
      businessName:
          '${businessJson['business_name'] ?? businessJson['display_name'] ?? ''}',
      slug: '${businessJson['slug'] ?? ''}',
      ownerUser: '${businessJson['owner_user'] ?? ''}',
      membershipRole: '${businessJson['membership_role'] ?? 'Owner'}',
      planType:
          '${businessJson['plan_type'] ?? json['plan_type'] ?? 'free_local'}',
      subscriptionStatus:
          '${businessJson['subscription_status'] ?? json['subscription_status'] ?? 'active'}',
      deploymentMode:
          '${businessJson['deployment_mode'] ?? json['deployment_mode'] ?? 'neuradix_cloud'}',
      planCaps: Map<String, Object?>.from(
        ((businessJson['plan_caps'] as Map?) ??
                (json['plan_caps'] as Map?) ??
                const <String, dynamic>{})
            .map((Object? key, dynamic value) => MapEntry('$key', value)),
      ),
      features: Map<String, bool>.from(
        ((businessJson['features'] as Map?) ??
                (json['features'] as Map?) ??
                const <String, dynamic>{})
            .map(
              (Object? key, dynamic value) =>
                  MapEntry('$key', value == true || value == 1 || value == '1'),
            ),
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'business': businessId,
      'business_name': businessName,
      'slug': slug,
      'owner_user': ownerUser,
      'membership_role': membershipRole,
      'plan_type': planType,
      'subscription_status': subscriptionStatus,
      'deployment_mode': deploymentMode,
      'plan_caps': planCaps,
      'features': features,
    };
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'business_id': businessId,
      'payload_json': jsonEncode(toJson()),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  HostedBusinessProfile copyWith({
    String? planType,
    String? subscriptionStatus,
    Map<String, Object?>? planCaps,
    Map<String, bool>? features,
  }) {
    return HostedBusinessProfile(
      businessId: businessId,
      businessName: businessName,
      slug: slug,
      ownerUser: ownerUser,
      membershipRole: membershipRole,
      planType: planType ?? this.planType,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      deploymentMode: deploymentMode,
      planCaps: planCaps ?? this.planCaps,
      features: features ?? this.features,
    );
  }
}

class HostedInventoryItem {
  const HostedInventoryItem({
    required this.itemId,
    required this.sku,
    required this.barcode,
    required this.displayName,
    required this.imageUrl,
    required this.price,
    required this.stockQty,
    required this.isActive,
    this.updatedAt = '',
  });

  final String itemId;
  final String sku;
  final String barcode;
  final String displayName;
  final String imageUrl;
  final double price;
  final double stockQty;
  final bool isActive;
  final String updatedAt;

  factory HostedInventoryItem.fromApi(Map<String, dynamic> json) {
    return HostedInventoryItem(
      itemId: '${json['name'] ?? json['item_id'] ?? ''}',
      sku: '${json['product_code'] ?? json['sku'] ?? ''}',
      barcode: '${json['barcode'] ?? ''}',
      displayName: '${json['product_name'] ?? json['display_name'] ?? ''}',
      imageUrl: '${json['image'] ?? json['image_url'] ?? ''}',
      price: double.tryParse('${json['price'] ?? 0}') ?? 0,
      stockQty: double.tryParse('${json['stock_qty'] ?? 0}') ?? 0,
      isActive:
          json['is_active'] == true ||
          json['is_active'] == 1 ||
          json['is_active'] == '1',
      updatedAt: '${json['modified'] ?? json['updated_at'] ?? ''}',
    );
  }

  factory HostedInventoryItem.fromRow(Map<String, Object?> row) {
    return HostedInventoryItem.fromApi(
      Map<String, dynamic>.from(jsonDecode('${row['payload_json']}') as Map),
    );
  }

  Map<String, Object?> toApiPayload() {
    return <String, Object?>{
      'item_id': itemId,
      'sku': sku,
      'barcode': barcode,
      'product_name': displayName,
      'image_url': imageUrl,
      'price': price,
      'stock_qty': stockQty,
      'is_active': isActive,
    };
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'item_id': itemId,
      'sku': sku,
      'barcode': barcode,
      'display_name': displayName,
      'image_url': imageUrl,
      'price': price,
      'stock_qty': stockQty,
      'is_active': isActive ? 1 : 0,
      'payload_json': jsonEncode(<String, Object?>{
        'name': itemId,
        'product_code': sku,
        'barcode': barcode,
        'product_name': displayName,
        'image': imageUrl,
        'price': price,
        'stock_qty': stockQty,
        'is_active': isActive ? 1 : 0,
        'updated_at': updatedAt,
      }),
      'updated_at':
          updatedAt.isEmpty ? DateTime.now().toIso8601String() : updatedAt,
    };
  }

  HostedInventoryItem copyWith({
    String? itemId,
    String? sku,
    String? barcode,
    String? displayName,
    String? imageUrl,
    double? price,
    double? stockQty,
    bool? isActive,
    String? updatedAt,
  }) {
    return HostedInventoryItem(
      itemId: itemId ?? this.itemId,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      displayName: displayName ?? this.displayName,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      stockQty: stockQty ?? this.stockQty,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class HostedCustomer {
  const HostedCustomer({
    required this.customerId,
    required this.customerCode,
    required this.displayName,
    required this.mobileNo,
    required this.emailId,
    required this.primaryAddress,
    required this.isActive,
    this.updatedAt = '',
  });

  final String customerId;
  final String customerCode;
  final String displayName;
  final String mobileNo;
  final String emailId;
  final String primaryAddress;
  final bool isActive;
  final String updatedAt;

  factory HostedCustomer.fromApi(Map<String, dynamic> json) {
    return HostedCustomer(
      customerId: '${json['name'] ?? json['customer_id'] ?? ''}',
      customerCode: '${json['customer_code'] ?? ''}',
      displayName: '${json['customer_name'] ?? json['display_name'] ?? ''}',
      mobileNo: '${json['mobile_no'] ?? ''}',
      emailId: '${json['email_id'] ?? json['email'] ?? ''}',
      primaryAddress: '${json['primary_address'] ?? ''}',
      isActive:
          json['is_active'] == true ||
          json['is_active'] == 1 ||
          json['is_active'] == '1',
      updatedAt: '${json['modified'] ?? json['updated_at'] ?? ''}',
    );
  }

  factory HostedCustomer.fromRow(Map<String, Object?> row) {
    return HostedCustomer.fromApi(
      Map<String, dynamic>.from(jsonDecode('${row['payload_json']}') as Map),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': customerId,
      'customer_code': customerCode,
      'customer_name': displayName,
      'mobile_no': mobileNo,
      'email_id': emailId,
      'primary_address': primaryAddress,
      'is_active': isActive ? 1 : 0,
      'updated_at': updatedAt,
    };
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'customer_id': customerId,
      'customer_code': customerCode,
      'display_name': displayName,
      'mobile_no': mobileNo,
      'email_id': emailId,
      'primary_address': primaryAddress,
      'is_active': isActive ? 1 : 0,
      'payload_json': jsonEncode(toJson()),
      'updated_at':
          updatedAt.isEmpty ? DateTime.now().toIso8601String() : updatedAt,
    };
  }

  HostedCustomer copyWith({
    String? customerId,
    String? customerCode,
    String? displayName,
    String? mobileNo,
    String? emailId,
    String? primaryAddress,
    bool? isActive,
    String? updatedAt,
  }) {
    return HostedCustomer(
      customerId: customerId ?? this.customerId,
      customerCode: customerCode ?? this.customerCode,
      displayName: displayName ?? this.displayName,
      mobileNo: mobileNo ?? this.mobileNo,
      emailId: emailId ?? this.emailId,
      primaryAddress: primaryAddress ?? this.primaryAddress,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class HostedSaleLine {
  const HostedSaleLine({
    required this.itemId,
    required this.displayName,
    required this.qty,
    required this.rate,
    this.notes = '',
  });

  final String itemId;
  final String displayName;
  final double qty;
  final double rate;
  final String notes;

  double get amount => qty * rate;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'item_id': itemId,
      'item_name': displayName,
      'qty': qty,
      'rate': rate,
      'amount': amount,
      'notes': notes,
    };
  }

  factory HostedSaleLine.fromJson(Map<String, dynamic> json) {
    return HostedSaleLine(
      itemId: '${json['item_id'] ?? json['item_code'] ?? ''}',
      displayName: '${json['item_name'] ?? json['display_name'] ?? ''}',
      qty: double.tryParse('${json['qty'] ?? 0}') ?? 0,
      rate: double.tryParse('${json['rate'] ?? 0}') ?? 0,
      notes: '${json['notes'] ?? ''}',
    );
  }
}

class HostedSaleRecord {
  const HostedSaleRecord({
    required this.saleId,
    required this.remoteSaleId,
    required this.customerId,
    required this.customerName,
    required this.postingDate,
    required this.totalAmount,
    required this.status,
    required this.items,
    this.updatedAt = '',
  });

  final String saleId;
  final String remoteSaleId;
  final String customerId;
  final String customerName;
  final String postingDate;
  final double totalAmount;
  final String status;
  final List<HostedSaleLine> items;
  final String updatedAt;

  factory HostedSaleRecord.fromJson(Map<String, dynamic> json) {
    final rows = (json['items'] as List?) ?? const <dynamic>[];
    return HostedSaleRecord(
      saleId:
          '${json['sale_id'] ?? json['client_sale_id'] ?? json['name'] ?? ''}',
      remoteSaleId:
          '${json['remote_sale_id'] ?? json['sale_id'] ?? json['name'] ?? ''}',
      customerId: '${json['customer_id'] ?? json['customer'] ?? ''}',
      customerName: '${json['customer_name'] ?? ''}',
      postingDate: '${json['posting_date'] ?? ''}',
      totalAmount: double.tryParse('${json['total_amount'] ?? 0}') ?? 0,
      status: '${json['status'] ?? 'local_only'}',
      items: rows
          .map(
            (dynamic row) =>
                HostedSaleLine.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      updatedAt: '${json['updated_at'] ?? json['modified'] ?? ''}',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sale_id': saleId,
      'remote_sale_id': remoteSaleId,
      'customer_id': customerId,
      'customer_name': customerName,
      'posting_date': postingDate,
      'total_amount': totalAmount,
      'status': status,
      'items': items.map((HostedSaleLine item) => item.toJson()).toList(),
      'updated_at': updatedAt,
    };
  }

  Map<String, Object?> toApiPayload() {
    return <String, Object?>{
      'client_sale_id': saleId,
      'customer_id': customerId,
      'customer_name': customerName,
      'posting_date': postingDate,
      'items': items.map((HostedSaleLine item) => item.toJson()).toList(),
    };
  }

  Map<String, Object?> toSaleRow() {
    return <String, Object?>{
      'sale_id': saleId,
      'remote_sale_id': remoteSaleId,
      'customer_id': customerId,
      'customer_name': customerName,
      'posting_date': postingDate,
      'total_amount': totalAmount,
      'status': status,
      'payload_json': jsonEncode(toJson()),
      'updated_at':
          updatedAt.isEmpty ? DateTime.now().toIso8601String() : updatedAt,
    };
  }
}

class HostedAuthResult {
  const HostedAuthResult({
    required this.sessionJson,
    required this.business,
    required this.subscriptionPlanType,
    required this.subscriptionStatus,
    required this.bootstrapJson,
  });

  final Map<String, dynamic> sessionJson;
  final HostedBusinessProfile business;
  final String subscriptionPlanType;
  final String subscriptionStatus;
  final Map<String, dynamic> bootstrapJson;
}

class HostedAuthAttempt {
  const HostedAuthAttempt({this.auth, this.error});

  final HostedAuthResult? auth;
  final Object? error;

  bool get isSuccess => auth != null;
}
