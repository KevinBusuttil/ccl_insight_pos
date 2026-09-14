import 'dart:io';

import 'package:flutter/widgets.dart';

import 'pos_models.dart';

ImageProvider<Object>? buildPlatformCatalogImageProvider({
  required String instanceUrl,
  required PosCatalogItem item,
}) {
  if (item.localImagePath.trim().isNotEmpty) {
    final file = File(item.localImagePath);
    if (file.existsSync()) {
      return FileImage(file);
    }
  }
  final resolvedUrl = _resolveCatalogImageUrl(instanceUrl, item.imageUrl);
  if (resolvedUrl.isEmpty) {
    return null;
  }
  return NetworkImage(resolvedUrl);
}

String _resolveCatalogImageUrl(String instanceUrl, String imageUrl) {
  final normalized = imageUrl.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    return normalized;
  }
  final base =
      instanceUrl.endsWith('/')
          ? instanceUrl.substring(0, instanceUrl.length - 1)
          : instanceUrl;
  if (normalized.startsWith('/')) {
    return '$base$normalized';
  }
  return '$base/$normalized';
}
