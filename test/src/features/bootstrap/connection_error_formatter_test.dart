import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/bootstrap/connection_error_formatter.dart';

void main() {
  test('formats macOS sandbox network failures with entitlement guidance', () {
    final message = formatConnectionError(
      Exception(
        'ClientException with SocketException: Connection failed '
        '(OS Error: Operation not permitted, errno = 1), '
        'address = 192.168.1.40, port = 8008',
      ),
      baseUrl: 'http://192.168.1.40:8008',
    );

    expect(message, contains('com.apple.security.network.client'));
    expect(message, contains('clean and rebuild the macOS target'));
    expect(message, contains('http://127.0.0.1:8008'));
    expect(message, contains('Use the LAN IP only from another device.'));
  });

  test('formats generic reachability failures with bench start guidance', () {
    final message = formatConnectionError(
      Exception('SocketException: Connection refused'),
      baseUrl: 'http://neuradix-cassar.localhost:8008',
    );

    expect(message, contains('Confirm `bench start` is running'));
    expect(message, contains('http://127.0.0.1:8008'));
    expect(message, contains('http://neuradix-cassar.localhost:8008'));
  });

  test('preserves non-network backend errors', () {
    const rawMessage = 'Invalid login credentials.';
    final message = formatConnectionError(
      Exception(rawMessage),
      baseUrl: 'http://neuradix-cassar.localhost:8008',
    );

    expect(message, rawMessage);
  });
}
