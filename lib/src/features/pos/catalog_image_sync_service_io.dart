import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'catalog_image_sync_service.dart';
import 'pos_models.dart';

class _IoCatalogImageSyncService implements CatalogImageSyncService {
  _IoCatalogImageSyncService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<List<PosImageManifestEntry>> syncImages({
    required List<PosImageManifestEntry> entries,
    required String instanceUrl,
    required String databasePath,
  }) async {
    if (entries.isEmpty || databasePath.isEmpty) {
      return entries;
    }

    final imageRoot = Directory(
      path.join(path.dirname(databasePath), 'catalog_images'),
    );
    await imageRoot.create(recursive: true);

    final syncedEntries = <PosImageManifestEntry>[];
    for (final entry in entries) {
      final resolvedUrl = _resolveCatalogImageUrl(instanceUrl, entry.imageUrl);
      if (resolvedUrl.isEmpty) {
        syncedEntries.add(entry);
        continue;
      }

      final fileName =
          '${_sanitize(entry.itemCode)}_${_sanitize(entry.imageVersion.isEmpty ? 'latest' : entry.imageVersion)}${_extensionFor(entry.imageUrl)}';
      final filePath = path.join(imageRoot.path, fileName);
      final file = File(filePath);
      if (await file.exists()) {
        syncedEntries.add(
          PosImageManifestEntry(
            itemCode: entry.itemCode,
            imageUrl: entry.imageUrl,
            imageVersion: entry.imageVersion,
            localPath: filePath,
          ),
        );
        continue;
      }

      try {
        final response = await _httpClient.get(Uri.parse(resolvedUrl));
        if (response.statusCode >= 400) {
          syncedEntries.add(entry);
          continue;
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
        syncedEntries.add(
          PosImageManifestEntry(
            itemCode: entry.itemCode,
            imageUrl: entry.imageUrl,
            imageVersion: entry.imageVersion,
            localPath: filePath,
          ),
        );
      } on Exception {
        syncedEntries.add(entry);
      }
    }
    return syncedEntries;
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

  String _sanitize(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _extensionFor(String imageUrl) {
    final uriPath = Uri.parse(imageUrl).path;
    final extension = path.extension(uriPath);
    return extension.isEmpty ? '.img' : extension;
  }
}

CatalogImageSyncService createPlatformCatalogImageSyncService() {
  return _IoCatalogImageSyncService();
}
