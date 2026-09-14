class LocalOrder {
  const LocalOrder({
    required this.clientOrderId,
    required this.customerId,
    required this.totalAmount,
    required this.payloadJson,
    required this.status,
    required this.updatedAtIso,
    this.remoteOrderId,
  });

  final String clientOrderId;
  final String customerId;
  final double totalAmount;
  final String payloadJson;
  final String status;
  final String updatedAtIso;
  final String? remoteOrderId;

  factory LocalOrder.fromRow(Map<String, Object?> row) {
    return LocalOrder(
      clientOrderId: '${row['client_order_id']}',
      customerId: '${row['customer_id']}',
      totalAmount: double.tryParse('${row['total_amount'] ?? 0}') ?? 0,
      payloadJson: '${row['payload_json']}',
      status: '${row['status']}',
      updatedAtIso: '${row['updated_at']}',
      remoteOrderId:
          row['remote_order_id'] == null ? null : '${row['remote_order_id']}',
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'client_order_id': clientOrderId,
      'customer_id': customerId,
      'total_amount': totalAmount,
      'status': status,
      'payload_json': payloadJson,
      'remote_order_id': remoteOrderId,
      'updated_at': updatedAtIso,
    };
  }
}

class SyncQueueEntry {
  const SyncQueueEntry({
    required this.clientOrderId,
    required this.action,
    required this.status,
    required this.payloadJson,
    required this.createdAtIso,
  });

  final String clientOrderId;
  final String action;
  final String status;
  final String payloadJson;
  final String createdAtIso;
}
