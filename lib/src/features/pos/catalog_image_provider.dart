import 'package:flutter/widgets.dart';

import 'catalog_image_provider_io.dart'
    if (dart.library.js_interop) 'catalog_image_provider_web.dart';
import 'pos_models.dart';

ImageProvider<Object>? buildCatalogImageProvider({
  required String instanceUrl,
  required PosCatalogItem item,
}) {
  return buildPlatformCatalogImageProvider(
    instanceUrl: instanceUrl,
    item: item,
  );
}
