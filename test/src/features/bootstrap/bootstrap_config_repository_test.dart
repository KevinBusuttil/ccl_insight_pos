import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/data/local/neuradix_database.dart';
import 'package:neuradix_pos/src/features/bootstrap/bootstrap_config.dart';
import 'package:neuradix_pos/src/features/bootstrap/bootstrap_config_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists and reloads bootstrap config', () async {
    sqfliteFfiInit();
    final database = NeuradixDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final openedDatabase = await database.open();
    final repository = BootstrapConfigRepository(openedDatabase);

    await repository.save(
      const BootstrapConfig(
        baseUrl: 'http://neuradix.example.com:8008',
        useSsl: false,
        deploymentMode: 'external_backend',
        planType: 'free_local',
        brandName: 'CassarCamilleri POS',
        supportEmail: 'support@neuradix.local',
        defaultCloudBaseUrl: 'http://cloud.neuradix.local:8008',
        themePrimary: '#2B6F77',
        themeSecondary: '#86A96F',
        themeAccent: '#5E6B73',
        themeTextOnPrimary: '#FFFFFF',
        themeSurface: '#F4F7F5',
        themeActive: '#355B66',
        syncMode: 'local_multi_shop',
        relayUrl: 'wss://relay.neuradix.test',
        protocolVersion: 2,
        metadataOnly: true,
        featureLocalMultiShopSync: true,
        shopId: 'SHOP-1',
        shopName: 'Main Shop',
      ),
    );

    final config = await repository.read();
    expect(config, isNotNull);
    expect(config?.baseUrl, 'http://neuradix.example.com:8008');
    expect(config?.useSsl, isFalse);
    expect(config?.deploymentMode, 'external_backend');
    expect(config?.planType, 'free_local');
    expect(config?.brandName, 'CassarCamilleri POS');
    expect(config?.supportEmail, 'support@neuradix.local');
    expect(config?.defaultCloudBaseUrl, 'http://cloud.neuradix.local:8008');
    expect(config?.themeSecondary, '#86A96F');
    expect(config?.themeAccent, '#5E6B73');
    expect(config?.syncMode, 'local_multi_shop');
    expect(config?.relayUrl, 'wss://relay.neuradix.test');
    expect(config?.protocolVersion, 2);
    expect(config?.metadataOnly, isTrue);
    expect(config?.featureLocalMultiShopSync, isTrue);
    expect(config?.shopId, 'SHOP-1');
    expect(config?.shopName, 'Main Shop');

    await database.close();
  });
}
