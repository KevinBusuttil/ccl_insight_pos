import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_models.dart';

void main() {
  test('metadata requires shop selection only for an untrusted register', () {
    final metadata = LocalSyncMetadata.fromJson(<String, Object?>{
      'business_id': 'NBIZ-1',
      'business_name': 'ABP',
      'relay_url': 'wss://relay.example.test',
      'protocol_version': 1,
      'max_devices': 10,
      'shops': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'SHOP-A',
          'shop_name': 'Valletta',
          'shop_code': 'VALLETTA',
          'status': 'active',
          'is_default': 1,
        },
        <String, Object?>{
          'name': 'SHOP-B',
          'shop_name': 'Sliema',
          'shop_code': 'SLIEMA',
          'status': 'active',
          'is_default': 0,
        },
      ],
      'devices': <Map<String, Object?>>[
        <String, Object?>{
          'device_id': 'trusted-a',
          'device_name': 'Valletta Till',
          'shop': 'SHOP-A',
          'shop_name': 'Valletta',
          'status': 'active',
          'is_preferred_peer': 1,
        },
      ],
    });

    expect(metadata.activeShops.map((shop) => shop.shopId), <String>[
      'SHOP-A',
      'SHOP-B',
    ]);
    expect(metadata.requiresShopSelectionFor('new-device'), isTrue);
    expect(metadata.requiresShopSelectionFor('trusted-a'), isFalse);
    expect(metadata.device('trusted-a')?.isPreferredPeer, isTrue);
  });
}
