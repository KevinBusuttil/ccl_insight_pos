import 'package:flutter/foundation.dart';

String formatConnectionError(
  Object error, {
  required String baseUrl,
  bool includePreviewHint = false,
  TargetPlatform? platform,
}) {
  final rawMessage = '$error'.trim();
  final message =
      rawMessage.startsWith('Exception: ')
          ? rawMessage.substring('Exception: '.length)
          : rawMessage;

  final Uri? uri = Uri.tryParse(baseUrl);
  final String scheme = uri?.scheme.isNotEmpty == true ? uri!.scheme : 'http';
  final int port = _resolvePort(uri, scheme);
  final String loopbackUrl = '$scheme://127.0.0.1:$port';
  final String aliasUrl = '$scheme://neuradix-cassar.localhost:$port';

  String formattedMessage = message;
  final effectivePlatform = platform ?? defaultTargetPlatform;
  if (effectivePlatform == TargetPlatform.macOS &&
      _looksLikeSandboxNetworkFailure(message)) {
    formattedMessage =
        'The macOS app is blocked from opening outbound network connections to '
        '$baseUrl. This usually means you are running an older macOS build '
        'without the latest sandbox entitlements. The current project already '
        'enables `com.apple.security.network.client`; clean and rebuild the '
        'macOS target, then retry. If the bench is running on this same Mac, '
        'prefer $loopbackUrl or $aliasUrl. Use the LAN IP only from another '
        'device.';
  } else if (_looksLikeReachabilityFailure(message)) {
    formattedMessage =
        'Unable to reach $baseUrl. Confirm `bench start` is running and that '
        'this URL is reachable from this device. If the bench is running on '
        'this same Mac, prefer $loopbackUrl or $aliasUrl. Use the LAN IP only '
        'from another device.';
  }

  if (!includePreviewHint) {
    return formattedMessage;
  }

  return '$formattedMessage You can still preview the rebuilt tablet flow locally.';
}

bool _looksLikeSandboxNetworkFailure(String message) {
  return _looksLikeReachabilityFailure(message) &&
      (message.contains('Operation not permitted') ||
          message.contains('errno = 1'));
}

bool _looksLikeReachabilityFailure(String message) {
  return message.contains('SocketException') ||
      message.contains('Connection failed') ||
      message.contains('Unable to reach the bench');
}

int _resolvePort(Uri? uri, String scheme) {
  if (uri == null) {
    return scheme == 'https' ? 443 : 8008;
  }
  if (uri.hasPort) {
    return uri.port;
  }
  if (scheme == 'https') {
    return 443;
  }
  return 8008;
}
