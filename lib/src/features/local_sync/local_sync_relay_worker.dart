import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'local_sync_coordinator.dart';
import 'local_sync_models.dart';

const localSyncOfflineMessage =
    'Local sync is offline. Changes stay queued on this device. '
    'Reconnect this register and at least one trusted register; '
    'sync retries automatically.';

enum LocalSyncRelayStatus { stopped, connecting, connected, offline }

abstract class LocalSyncRelaySocket {
  Stream<Object?> get messages;

  void send(String frame);

  Future<void> close();
}

typedef LocalSyncRelayConnector =
    Future<LocalSyncRelaySocket> Function(Uri uri);
typedef LocalSyncRelayTokenProvider = Future<Map<String, dynamic>> Function();
typedef LocalSyncMetadataRefresher = Future<Map<String, dynamic>> Function();
typedef LocalSyncRelayCallback = FutureOr<void> Function();
typedef LocalSyncRelayStatusCallback =
    void Function(LocalSyncRelayStatus status, String message);

class WebSocketLocalSyncRelaySocket implements LocalSyncRelaySocket {
  WebSocketLocalSyncRelaySocket._(this._channel);

  final WebSocketChannel _channel;

  static Future<WebSocketLocalSyncRelaySocket> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return WebSocketLocalSyncRelaySocket._(channel);
  }

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  void send(String frame) => _channel.sink.add(frame);

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

class LocalSyncRelayWorker {
  LocalSyncRelayWorker({
    required this.coordinator,
    required this.issueToken,
    required this.refreshMetadata,
    this.onDataChanged,
    this.onStatusChanged,
    LocalSyncRelayConnector? connector,
    this.periodicInterval = const Duration(seconds: 2),
  }) : _connector = connector ?? WebSocketLocalSyncRelaySocket.connect;

  final LocalSyncCoordinator coordinator;
  final LocalSyncRelayTokenProvider issueToken;
  final LocalSyncMetadataRefresher refreshMetadata;
  final LocalSyncRelayCallback? onDataChanged;
  final LocalSyncRelayStatusCallback? onStatusChanged;
  final Duration periodicInterval;
  final LocalSyncRelayConnector _connector;

  LocalSyncRelaySocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _timer;
  Future<void>? _connectFuture;
  Future<void> _messageQueue = Future<void>.value();
  bool _stopped = true;
  bool _flushing = false;

  bool get isConnected => _socket != null;

  Future<void> start() async {
    if (!_stopped) {
      return;
    }
    _stopped = false;
    _timer = Timer.periodic(periodicInterval, (_) {
      unawaited(_tick());
    });
    await _ensureConnected();
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _emitStatus(LocalSyncRelayStatus.stopped, 'Local sync stopped.');
  }

  Future<void> flushPending() async {
    final socket = _socket;
    if (_stopped || socket == null || _flushing) {
      return;
    }
    _flushing = true;
    try {
      final pending = await coordinator.repository.readPendingEvents();
      for (final event in pending) {
        try {
          socket.send(
            jsonEncode(<String, Object?>{
              'type': 'event',
              'envelope': event.envelope.toJson(),
            }),
          );
          await coordinator.repository.markSent(event.envelope.eventId);
        } on Object catch (error) {
          await coordinator.repository.markRetry(event.envelope.eventId, error);
          rethrow;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _tick() async {
    if (_stopped) {
      return;
    }
    if (_socket == null) {
      await _ensureConnected();
      return;
    }
    await flushPending();
  }

  Future<void> _ensureConnected() {
    if (_stopped || _socket != null) {
      return Future<void>.value();
    }
    return _connectFuture ??= _connect().whenComplete(() {
      _connectFuture = null;
    });
  }

  Future<void> _connect() async {
    _emitStatus(
      LocalSyncRelayStatus.connecting,
      'Connecting to trusted registers.',
    );
    try {
      final issued = await issueToken();
      final relayUrl = normalizeLocalSyncRelayUrlForRuntime(
        '${issued['relay_url'] ?? coordinator.profile.relayUrl}',
      );
      final token = '${issued['token'] ?? ''}';
      if (relayUrl.isEmpty || token.isEmpty) {
        throw StateError('The relay URL or relay token is missing.');
      }
      final baseUri = Uri.parse(relayUrl);
      final uri = baseUri.replace(
        queryParameters: <String, String>{
          ...baseUri.queryParameters,
          'token': token,
        },
      );
      final socket = await _connector(uri);
      if (_stopped) {
        await socket.close();
        return;
      }
      _socket = socket;
      _subscription = socket.messages.listen(
        (Object? frame) {
          _messageQueue = _messageQueue
              .then((_) => _handleFrame(frame))
              .catchError((Object error) {
                _emitStatus(
                  LocalSyncRelayStatus.offline,
                  'A local sync frame was rejected: $error',
                );
              });
        },
        onError: (Object error, StackTrace stackTrace) {
          _handleDisconnect(localSyncOfflineMessage);
        },
        onDone: () {
          _handleDisconnect(localSyncOfflineMessage);
        },
        cancelOnError: false,
      );
      _emitStatus(
        LocalSyncRelayStatus.connected,
        'Connected to trusted registers.',
      );
      await _refreshTrustedPeers();
      await flushPending();
    } on Object catch (_) {
      _handleDisconnect(localSyncOfflineMessage);
    }
  }

  Future<void> _handleFrame(Object? rawFrame) async {
    final frame = _decodeFrame(rawFrame);
    switch ('${frame['type'] ?? ''}') {
      case 'hello':
      case 'peer_state':
        await _refreshTrustedPeers();
        await flushPending();
        return;
      case 'event':
        final rawEnvelope = frame['envelope'];
        if (rawEnvelope is! Map) {
          throw const FormatException('Relay event has no envelope.');
        }
        final envelope = LocalSyncEnvelope.fromJson(
          Map<String, dynamic>.from(rawEnvelope),
        );
        LocalSyncApplyResult result;
        try {
          result = await coordinator.applyEnvelope(envelope);
        } on StateError catch (error) {
          if (!error.toString().contains('trusted device')) {
            rethrow;
          }
          await _refreshTrustedPeers();
          result = await coordinator.applyEnvelope(envelope);
        }
        _socket?.send(
          jsonEncode(<String, Object?>{
            'type': 'ack',
            'event_id': envelope.eventId,
            'origin_device_id': envelope.originDeviceId,
            'peer_device_id': coordinator.profile.deviceId,
          }),
        );
        if (result.materialized) {
          await onDataChanged?.call();
        }
        return;
      case 'ack':
        if ('${frame['origin_device_id'] ?? ''}' !=
            coordinator.profile.deviceId) {
          return;
        }
        await coordinator.repository.acknowledge(
          eventId: '${frame['event_id'] ?? ''}',
          peerDeviceId: '${frame['peer_device_id'] ?? ''}',
        );
        return;
      case 'pong':
        return;
      case 'error':
        _emitStatus(
          LocalSyncRelayStatus.offline,
          'Relay rejected a frame: ${frame['message'] ?? 'unknown error'}',
        );
        return;
      default:
        throw FormatException('Unsupported relay frame: ${frame['type']}');
    }
  }

  Future<void> _refreshTrustedPeers() async {
    final metadata = await refreshMetadata();
    await coordinator.refreshTrustedPeers(metadata);
  }

  Map<String, dynamic> _decodeFrame(Object? rawFrame) {
    final value = rawFrame is List<int> ? utf8.decode(rawFrame) : '$rawFrame';
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Relay frame must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _handleDisconnect(String message) {
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
    if (!_stopped) {
      _emitStatus(LocalSyncRelayStatus.offline, message);
    }
  }

  void _emitStatus(LocalSyncRelayStatus status, String message) {
    onStatusChanged?.call(status, message);
  }
}

String normalizeLocalSyncRelayUrlForRuntime(
  String relayUrl, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final trimmed = relayUrl.trim();
  if (trimmed.isEmpty || isWeb) {
    return trimmed;
  }
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  if (resolvedPlatform != TargetPlatform.android) {
    return trimmed;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !<String>{
        '127.0.0.1',
        'localhost',
        'neuradix-cloud.localhost',
      }.contains(uri.host)) {
    return trimmed;
  }
  return uri.replace(host: '10.0.2.2').toString();
}
