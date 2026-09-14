import 'package:flutter/foundation.dart';

const String _androidEmulatorLoopback = '10.0.2.2';

const Set<String> _androidAliasHosts = <String>{
  '127.0.0.1',
  'localhost',
  'neuradix-cassar.localhost',
  'neuradix-cloud.localhost',
};

String normalizeBenchUrlForRuntime(
  String baseUrl, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty || isWeb) {
    return trimmed;
  }

  final resolvedPlatform = platform ?? defaultTargetPlatform;
  if (resolvedPlatform != TargetPlatform.android) {
    return trimmed;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !_androidAliasHosts.contains(uri.host)) {
    return trimmed;
  }

  return uri.replace(host: _androidEmulatorLoopback).toString();
}
