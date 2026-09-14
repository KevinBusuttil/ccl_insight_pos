import 'catalog_image_sync_service.dart';
import 'pos_models.dart';

class _WebCatalogImageSyncService implements CatalogImageSyncService {
  @override
  Future<List<PosImageManifestEntry>> syncImages({
    required List<PosImageManifestEntry> entries,
    required String instanceUrl,
    required String databasePath,
  }) async {
    return entries;
  }
}

CatalogImageSyncService createPlatformCatalogImageSyncService() {
  return _WebCatalogImageSyncService();
}
