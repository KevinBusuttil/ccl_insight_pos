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
typedef LocalSyncClock = DateTime Function();

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
    this.heartbeatInterval = const Duration(seconds: 10),
    this.heartbeatTimeout = const Duration(seconds: 45),
    this.metadataRefreshInterval = const Duration(seconds: 30),
    LocalSyncClock? clock,
  }) : _connector = connector ?? WebSocketLocalSyncRelaySocket.connect,
       _clock = clock ?? DateTime.now;

  final LocalSyncCoordinator coordinator;
  final LocalSyncRelayTokenProvider issueToken;
  final LocalSyncMetadataRefresher refreshMetadata;
  final LocalSyncRelayCallback? onDataChanged;
  final LocalSyncRelayStatusCallback? onStatusChanged;
  final Duration periodicInterval;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final Duration metadataRefreshInterval;
  final LocalSyncRelayConnector _connector;
  final LocalSyncClock _clock;

  LocalSyncRelaySocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _timer;
  Future<void>? _connectFuture;
  Future<bool>? _reconnectFuture;
  Future<void> _messageQueue = Future<void>.value();
  bool _stopped = true;
  bool _flushing = false;
  DateTime? _lastInboundAt;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastMetadataRefreshAt;
  final Set<String> _onlineDeviceIds = <String>{};

  bool get isConnected => _socket != null;
  int get onlinePeerCount => _onlineDeviceIds.length;

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
    final socket = _socket;
    if (socket != null) {
      await _retireSocket(socket, emitOffline: false);
    }
    _emitStatus(LocalSyncRelayStatus.stopped, 'Local sync stopped.');
  }

  Future<bool> reconnectAndFlush() {
    return _reconnectFuture ??= _replaceConnectionAndFlush().whenComplete(() {
      _reconnectFuture = null;
    });
  }

  Future<bool> _replaceConnectionAndFlush() async {
    if (_stopped) {
      await start();
    } else {
      final connecting = _connectFuture;
      if (connecting != null) {
        await connecting;
      }
      final socket = _socket;
      if (socket != null) {
        await _retireSocket(socket, emitOffline: false);
      }
      await _ensureConnected();
    }
    final socket = _socket;
    if (socket == null) {
      return false;
    }
    try {
      await _sendHeartbeatIfDue(socket, force: true);
      await flushPending();
      return identical(_socket, socket);
    } on Object {
      await _retireSocket(socket, emitOffline: true);
      return false;
    }
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
        if (!identical(_socket, socket)) {
          return;
        }
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
    final socket = _socket;
    if (socket == null) {
      return;
    }
    final now = _clock();
    final lastInboundAt = _lastInboundAt;
    if (lastInboundAt != null &&
        now.difference(lastInboundAt) >= heartbeatTimeout) {
      await _retireSocket(socket, emitOffline: true);
      await _ensureConnected();
      return;
    }
    try {
      await _sendHeartbeatIfDue(socket);
      await _refreshTrustedPeersIfDue();
      await flushPending();
    } on Object {
      await _retireSocket(socket, emitOffline: true);
      await _ensureConnected();
    }
  }

  @visibleForTesting
  Future<void> runMaintenanceCycle() => _tick();

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
    LocalSyncRelaySocket? connectedSocket;
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
      connectedSocket = socket;
      if (_stopped) {
        await socket.close();
        return;
      }
      _socket = socket;
      _lastInboundAt = _clock();
      _lastHeartbeatAt = null;
      _lastMetadataRefreshAt = null;
      _onlineDeviceIds.clear();
      _subscription = socket.messages.listen(
        (Object? frame) {
          if (!identical(_socket, socket)) {
            return;
          }
          _lastInboundAt = _clock();
          _messageQueue = _messageQueue
              .then((_) => _handleFrame(frame, socket))
              .catchError((Object error) {
                if (identical(_socket, socket)) {
                  _emitStatus(
                    LocalSyncRelayStatus.connected,
                    'Relay connected, but a sync frame was rejected: $error',
                  );
                }
              });
        },
        onError: (Object error, StackTrace stackTrace) {
          _handleDisconnect(socket, localSyncOfflineMessage);
        },
        onDone: () {
          _handleDisconnect(socket, localSyncOfflineMessage);
        },
        cancelOnError: false,
      );
      _emitConnectedStatus();
      await _sendHeartbeatIfDue(socket, force: true);
      try {
        await _refreshTrustedPeers();
      } on Object {
        _emitStatus(
          LocalSyncRelayStatus.connected,
          'Relay connected; trusted-register metadata will retry.',
        );
      }
      await flushPending();
    } on Object catch (_) {
      final socket = connectedSocket;
      if (socket != null && identical(_socket, socket)) {
        await _retireSocket(socket, emitOffline: true);
      } else if (!_stopped) {
        _emitStatus(LocalSyncRelayStatus.offline, localSyncOfflineMessage);
      }
    }
  }

  Future<void> _handleFrame(
    Object? rawFrame,
    LocalSyncRelaySocket sourceSocket,
  ) async {
    if (!identical(_socket, sourceSocket)) {
      return;
    }
    final frame = _decodeFrame(rawFrame);
    switch ('${frame['type'] ?? ''}') {
      case 'hello':
        final onlineDevices = (frame['online_devices'] as List? ?? const [])
            .map((Object? value) => '$value')
            .where(
              (String deviceId) =>
                  deviceId.isNotEmpty &&
                  deviceId != coordinator.profile.deviceId,
            );
        _onlineDeviceIds
          ..clear()
          ..addAll(onlineDevices);
        _emitConnectedStatus();
        await _refreshTrustedPeers();
        await flushPending();
        return;
      case 'peer_state':
        final deviceId = '${frame['device_id'] ?? ''}';
        if (deviceId.isNotEmpty && deviceId != coordinator.profile.deviceId) {
          if (frame['online'] == true) {
            _onlineDeviceIds.add(deviceId);
          } else {
            _onlineDeviceIds.remove(deviceId);
          }
        }
        _emitConnectedStatus();
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
        sourceSocket.send(
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
          LocalSyncRelayStatus.connected,
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
    _lastMetadataRefreshAt = _clock();
  }

  Future<void> _refreshTrustedPeersIfDue() async {
    final lastRefresh = _lastMetadataRefreshAt;
    if (lastRefresh != null &&
        _clock().difference(lastRefresh) < metadataRefreshInterval) {
      return;
    }
    try {
      await _refreshTrustedPeers();
    } on Object {
      if (_socket != null) {
        _emitStatus(
          LocalSyncRelayStatus.connected,
          'Relay connected; trusted-register metadata will retry.',
        );
      }
    }
  }

  Future<void> _sendHeartbeatIfDue(
    LocalSyncRelaySocket socket, {
    bool force = false,
  }) async {
    if (!identical(_socket, socket)) {
      return;
    }
    final now = _clock();
    final lastHeartbeatAt = _lastHeartbeatAt;
    if (!force &&
        lastHeartbeatAt != null &&
        now.difference(lastHeartbeatAt) < heartbeatInterval) {
      return;
    }
    socket.send(jsonEncode(const <String, Object?>{'type': 'ping'}));
    _lastHeartbeatAt = now;
  }

  Map<String, dynamic> _decodeFrame(Object? rawFrame) {
    final value = rawFrame is List<int> ? utf8.decode(rawFrame) : '$rawFrame';
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Relay frame must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _handleDisconnect(LocalSyncRelaySocket socket, String message) {
    unawaited(_retireSocket(socket, emitOffline: true, message: message));
  }

  Future<void> _retireSocket(
    LocalSyncRelaySocket socket, {
    required bool emitOffline,
    String message = localSyncOfflineMessage,
  }) async {
    if (!identical(_socket, socket)) {
      return;
    }
    final subscription = _subscription;
    _subscription = null;
    _socket = null;
    _lastInboundAt = null;
    _lastHeartbeatAt = null;
    _lastMetadataRefreshAt = null;
    _onlineDeviceIds.clear();
    try {
      await subscription?.cancel();
    } on Object {
      // The connection is already retired locally; cancellation is best effort.
    }
    try {
      await socket.close();
    } on Object {
      // A half-open transport commonly fails while closing; reconnection continues.
    }
    if (!_stopped && emitOffline) {
      _emitStatus(LocalSyncRelayStatus.offline, message);
    }
  }

  void _emitConnectedStatus() {
    final peers = onlinePeerCount;
    _emitStatus(
      LocalSyncRelayStatus.connected,
      peers == 0
          ? 'Relay connected; waiting for another trusted register.'
          : 'Relay connected to $peers trusted ${peers == 1 ? 'register' : 'registers'}.',
    );
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
