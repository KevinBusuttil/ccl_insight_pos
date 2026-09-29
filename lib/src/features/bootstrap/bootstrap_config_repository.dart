import 'package:sqflite/sqflite.dart';

import 'bootstrap_config.dart';
import 'runtime_bench_url.dart';

class BootstrapConfigRepository {
  BootstrapConfigRepository(this.database);

  final Database database;

  Future<void> save(BootstrapConfig config) async {
    final batch = database.batch();
    config.asMap().forEach((String key, String value) {
      batch.insert('app_config', <String, Object?>{
        'config_key': key,
        'config_value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  Future<BootstrapConfig?> read() async {
    final rows = await database.query('app_config');
    if (rows.isEmpty) {
      return null;
    }

    final values = <String, String>{};
    for (final row in rows) {
      values['${row['config_key']}'] = '${row['config_value']}';
    }

    final baseUrl = normalizeBenchUrlForRuntime(values['base_url'] ?? '');
    if (baseUrl.isEmpty) {
      return null;
    }

    final planType = values['plan_type'] ?? 'free_local';
    return BootstrapConfig(
      baseUrl: baseUrl,
      useSsl: values['use_ssl'] == '1',
      deploymentMode: values['deployment_mode'] ?? 'external_backend',
      planType: planType,
      brandName: values['brand_name'] ?? 'Neuradix POS',
      supportEmail: values['support_email'] ?? 'support@neuradix.local',
      defaultCloudBaseUrl: normalizeBenchUrlForRuntime(
        values['default_cloud_base_url'] ?? neuradixDefaultCloudBaseUrlFallback,
      ),
      themePrimary: values['theme_primary'] ?? '#2B6F77',
      themeSecondary: values['theme_secondary'] ?? '#86A96F',
      themeAccent: values['theme_accent'] ?? '#5E6B73',
      themeTextOnPrimary: values['theme_text_on_primary'] ?? '#FFFFFF',
      themeSurface: values['theme_surface'] ?? '#F4F7F5',
      themeActive: values['theme_active'] ?? '#355B66',
      businessId: values['business_id'] ?? '',
      businessName: values['business_name'] ?? '',
      deviceId: values['device_id'] ?? '',
      deviceName: values['device_name'] ?? '',
      syncMode:
          values['sync_mode'] ??
          ((planType == 'free_cloud' || planType == 'paid_cloud')
              ? 'hosted_backend'
              : 'device_local'),
      relayUrl: values['relay_url'] ?? '',
      protocolVersion: int.tryParse(values['protocol_version'] ?? '') ?? 1,
      metadataOnly: values['metadata_only'] == '1',
      featureLocalMultiShopSync: values['feature_local_multi_shop_sync'] == '1',
      shopId: values['shop_id'] ?? '',
      shopName: values['shop_name'] ?? '',
    );
  }
}
