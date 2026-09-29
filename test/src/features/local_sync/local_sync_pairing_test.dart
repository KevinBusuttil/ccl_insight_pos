import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/local_sync/local_sync_pairing.dart';

void main() {
  test('pairing code round trips without unsafe input characters', () {
    final code = encodeLocalSyncPairingCode(<String, Object?>{
      'business_id': 'NBIZ-1',
      'enrollment_id': 'NENR-1',
      'device_id': 'device-2',
      'exchange_public_key': 'a+/=',
    });

    expect(code, isNot(contains('=')));
    expect(decodeLocalSyncPairingCode(code)['device_id'], 'device-2');
  });

  test('pairing code rejects missing trust fields', () {
    final code = encodeLocalSyncPairingCode(<String, Object?>{
      'business_id': 'NBIZ-1',
    });

    expect(() => decodeLocalSyncPairingCode(code), throwsFormatException);
  });
}
