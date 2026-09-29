import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../local_sync/local_sync_ids.dart';
import 'hosted_models.dart';

String hostedCustomerSearchLabel(HostedCustomer customer) {
  final code = customer.customerCode.trim();
  final name = customer.displayName.trim();
  return code.isEmpty ? name : '$code • $name';
}

bool hostedCustomerMatchesQuery(HostedCustomer customer, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  return customer.displayName.toLowerCase().contains(normalized) ||
      customer.customerCode.toLowerCase().contains(normalized) ||
      customer.mobileNo.toLowerCase().contains(normalized);
}

String hostedInventorySearchLabel(HostedInventoryItem item) {
  final segments = <String>[item.displayName.trim()];
  if (item.sku.trim().isNotEmpty) {
    segments.add(item.sku.trim());
  }
  if (item.barcode.trim().isNotEmpty) {
    segments.add(item.barcode.trim());
  }
  return segments.join(' • ');
}

bool hostedInventoryMatchesQuery(HostedInventoryItem item, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  return item.displayName.toLowerCase().contains(normalized) ||
      item.sku.toLowerCase().contains(normalized) ||
      item.barcode.toLowerCase().contains(normalized);
}

HostedInventoryItem? findHostedInventoryExactMatch(
  Iterable<HostedInventoryItem> items,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  for (final item in items) {
    if (item.barcode.trim().toLowerCase() == normalized ||
        item.sku.trim().toLowerCase() == normalized ||
        item.displayName.trim().toLowerCase() == normalized) {
      return item;
    }
  }
  return null;
}

String hostedImageMimeTypeFromFileName(String fileName) {
  switch (path.extension(fileName).toLowerCase()) {
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    case '.bmp':
      return 'image/bmp';
    default:
      return 'application/octet-stream';
  }
}

String hostedImageDataUri({
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
}) {
  final effectiveMimeType =
      (mimeType?.trim().isNotEmpty ?? false)
          ? mimeType!.trim()
          : hostedImageMimeTypeFromFileName(fileName);
  return 'data:$effectiveMimeType;base64,${base64Encode(bytes)}';
}

Uint8List? decodeHostedImageDataUri(String imageUrl) {
  if (!imageUrl.startsWith('data:')) {
    return null;
  }
  final commaIndex = imageUrl.indexOf(',');
  if (commaIndex < 0 || commaIndex + 1 >= imageUrl.length) {
    return null;
  }
  try {
    return base64Decode(imageUrl.substring(commaIndex + 1));
  } on FormatException {
    return null;
  }
}

String? localSyncShopReassignmentBlockReason({
  required int pendingEvents,
  required int parkedOrders,
  required int queuedOrders,
  required int activeCartLines,
}) {
  if (activeCartLines > 0) {
    return 'Complete or clear the active cart before changing this register shop.';
  }
  if (pendingEvents > 0 || parkedOrders > 0 || queuedOrders > 0) {
    return 'Shop reassignment is blocked until $pendingEvents sync event(s), '
        '$parkedOrders parked order(s), and $queuedOrders queued order(s) are cleared.';
  }
  return null;
}

String hostedResolveImageUrl({
  required String imageUrl,
  required String baseUrl,
}) {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty || trimmed.startsWith('data:')) {
    return trimmed;
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) {
    return trimmed;
  }
  final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
  return base
      .resolve(trimmed.startsWith('/') ? trimmed.substring(1) : trimmed)
      .toString();
}

String hostedLocalInventoryId([DateTime? timestamp]) {
  final effectiveTimestamp = timestamp ?? DateTime.now();
  return 'local-item-${effectiveTimestamp.microsecondsSinceEpoch}';
}

String hostedLocalCustomerId([DateTime? timestamp]) {
  if (timestamp != null) {
    return 'local-customer-${timestamp.microsecondsSinceEpoch}';
  }
  return 'local-customer-${generateLocalSyncId()}';
}

HostedInventoryItem normalizeHostedInventoryDraftForSave(
  HostedInventoryItem item, {
  required bool syncToCloud,
  DateTime? timestamp,
}) {
  final normalizedItemId = item.itemId.trim();
  if (syncToCloud) {
    if (normalizedItemId.startsWith('NPROD-')) {
      return item.copyWith(itemId: normalizedItemId);
    }
    return item.copyWith(itemId: '');
  }
  if (normalizedItemId.isNotEmpty) {
    return item.copyWith(itemId: normalizedItemId);
  }
  return item.copyWith(itemId: hostedLocalInventoryId(timestamp));
}

HostedCustomer normalizeHostedCustomerDraftForSave(
  HostedCustomer customer, {
  required bool syncToCloud,
  DateTime? timestamp,
}) {
  final normalizedCustomerId = customer.customerId.trim();
  if (syncToCloud) {
    if (normalizedCustomerId.startsWith('NCUST-')) {
      return customer.copyWith(customerId: normalizedCustomerId);
    }
    return customer.copyWith(customerId: '');
  }
  if (normalizedCustomerId.isNotEmpty) {
    return customer.copyWith(customerId: normalizedCustomerId);
  }
  return customer.copyWith(customerId: hostedLocalCustomerId(timestamp));
}

List<HostedSaleLine> hostedCartAfterSaleFailure({
  required Iterable<HostedSaleLine> currentCart,
  required bool savedLocally,
}) {
  if (savedLocally) {
    return <HostedSaleLine>[];
  }
  return List<HostedSaleLine>.from(currentCart);
}
