import 'dart:convert';

String encodeLocalSyncPairingCode(Map<String, Object?> payload) {
  return base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
}

Map<String, dynamic> decodeLocalSyncPairingCode(String code) {
  final normalized = code.trim().replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) {
    throw const FormatException('Enter the pairing code from the new device.');
  }
  final padded = normalized.padRight(
    normalized.length + ((4 - normalized.length % 4) % 4),
    '=',
  );
  final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
  if (decoded is! Map) {
    throw const FormatException('The pairing code is invalid.');
  }
  final payload = Map<String, dynamic>.from(decoded);
  const requiredFields = <String>{
    'business_id',
    'enrollment_id',
    'device_id',
    'exchange_public_key',
  };
  for (final field in requiredFields) {
    if ('${payload[field] ?? ''}'.trim().isEmpty) {
      throw FormatException('The pairing code has no $field.');
    }
  }
  return payload;
}
