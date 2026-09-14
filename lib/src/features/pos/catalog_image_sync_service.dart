import 'pos_models.dart';
import 'catalog_image_sync_service_io.dart'
    if (dart.library.js_interop) 'catalog_image_sync_service_web.dart';

abstract class CatalogImageSyncService {
  Future<List<PosImageManifestEntry>> syncImages({
    required List<PosImageManifestEntry> entries,
    required String instanceUrl,
    required String databasePath,
  });
}

CatalogImageSyncService createCatalogImageSyncService() {
  return createPlatformCatalogImageSyncService();
}
