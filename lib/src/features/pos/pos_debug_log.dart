import 'package:flutter/foundation.dart';

import 'pos_models.dart';

class PosDebugLog {
  const PosDebugLog._();

  static void info(String scope, String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[NEURADIX][$scope] $message');
  }

  static String summarizeCustomers(
    List<PosCustomer> customers, {
    int maxItems = 3,
  }) {
    final sample = customers
        .take(maxItems)
        .map(
          (PosCustomer customer) =>
              '${customer.displayName}<${customer.id}>/${customer.customerCode}/${customer.mobileNo}',
        )
        .join(', ');
    final unnamedCount =
        customers
            .where(
              (PosCustomer customer) => customer.displayName.trim().isEmpty,
            )
            .length;
    final missingIdCount =
        customers
            .where((PosCustomer customer) => customer.id.trim().isEmpty)
            .length;
    return 'count=${customers.length} unnamed=$unnamedCount missing_id=$missingIdCount sample=[$sample]';
  }

  static String summarizeCustomerMaps(
    List<Map<String, dynamic>> rows, {
    int maxItems = 3,
  }) {
    final sample = rows
        .take(maxItems)
        .map((Map<String, dynamic> row) {
          final name = '${row['customer_name'] ?? row['name'] ?? ''}';
          final id = '${row['name'] ?? ''}';
          final code = '${row['custom_customer_id'] ?? ''}';
          final mobile = '${row['mobile_no'] ?? ''}';
          return '$name<$id>/$code/$mobile';
        })
        .join(', ');
    final unnamedCount =
        rows
            .where(
              (Map<String, dynamic> row) =>
                  '${row['customer_name'] ?? row['name'] ?? ''}'.trim().isEmpty,
            )
            .length;
    final missingIdCount =
        rows
            .where(
              (Map<String, dynamic> row) =>
                  '${row['name'] ?? ''}'.trim().isEmpty,
            )
            .length;
    return 'count=${rows.length} unnamed=$unnamedCount missing_id=$missingIdCount sample=[$sample]';
  }
}
