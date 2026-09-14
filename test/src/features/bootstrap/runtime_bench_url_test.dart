import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/bootstrap/runtime_bench_url.dart';

void main() {
  test('android emulator maps localhost aliases to 10.0.2.2', () {
    expect(
      normalizeBenchUrlForRuntime(
        'http://127.0.0.1:8018',
        platform: TargetPlatform.android,
        isWeb: false,
      ),
      'http://10.0.2.2:8018',
    );
    expect(
      normalizeBenchUrlForRuntime(
        'http://neuradix-cloud.localhost:8018',
        platform: TargetPlatform.android,
        isWeb: false,
      ),
      'http://10.0.2.2:8018',
    );
  });

  test('non-android platforms keep the configured bench URL', () {
    expect(
      normalizeBenchUrlForRuntime(
        'http://neuradix-cloud.localhost:8018',
        platform: TargetPlatform.macOS,
        isWeb: false,
      ),
      'http://neuradix-cloud.localhost:8018',
    );
  });

  test('web keeps the configured bench URL unchanged', () {
    expect(
      normalizeBenchUrlForRuntime(
        'http://127.0.0.1:8018',
        platform: TargetPlatform.android,
        isWeb: true,
      ),
      'http://127.0.0.1:8018',
    );
  });
}
