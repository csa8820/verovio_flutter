import 'dart:async';
import 'dart:isolate';

import 'package:verovio_flutter/src/verovio_exception.dart';
import 'package:verovio_flutter/src/verovio_isolate_worker.dart';
import 'package:verovio_flutter/src/worker/worker_client.dart';

/// IO (isolate-based) implementation of [VerovioWorkerClient].
final class VerovioWorkerClientIO extends VerovioWorkerClient {
  VerovioWorkerClientIO._(
    this._isolate,
    this._controlPort,
    this._responsePort,
  ) {
    _responseSubscription = _responsePort.listen(_handleResponse);
  }

  final Isolate _isolate;
  final SendPort _controlPort;
  final ReceivePort _responsePort;
  late final StreamSubscription<dynamic> _responseSubscription;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  int _nextRequestId = 0;
  bool _disposed = false;

  /// Spawns a worker isolate and creates an IO client.
  static Future<VerovioWorkerClientIO> connect({
    required String resourcePath,
  }) async {
    final handshakePort = ReceivePort();
    final responsePort = ReceivePort();
    final isolate = await Isolate.spawn(
      verovioIsolateWorkerEntryPoint,
      <String, Object?>{
        'handshakePort': handshakePort.sendPort,
        'responsePort': responsePort.sendPort,
      },
    );
    final controlPort = await handshakePort.first as SendPort;
    final client = VerovioWorkerClientIO._(
      isolate,
      controlPort,
      responsePort,
    );
    try {
      await client.sendRaw('spawn', <String, Object?>{
        'resourcePath': resourcePath,
      });
      return client;
    } catch (_) {
      await client.forceDispose();
      rethrow;
    }
  }

  void _handleResponse(dynamic message) {
    if (message is! Map) {
      return;
    }
    final requestId = message['requestId'];
    if (requestId is! int) {
      return;
    }
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete(message.cast<String, Object?>());
  }

  @override
  Future<Object?> sendRaw(String action,
      [Map<String, Object?> payload = const <String, Object?>{}]) async {
    if (_disposed) {
      throw StateError('VerovioAsyncService has been disposed');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[requestId] = completer;
    _controlPort.send(<String, Object?>{
      'requestId': requestId,
      'action': action,
      'payload': payload,
    });
    final response = await completer.future;
    if (response['ok'] == true) {
      return response['result'];
    }
    throw VerovioException(
      method: action,
      log: response['error']?.toString() ?? '',
    );
  }

  @override
  Future<void> forceDispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('VerovioAsyncService has been disposed'),
        );
      }
    }
    _pending.clear();
    await _responseSubscription.cancel();
    _responsePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    try {
      await sendRaw('dispose');
    } finally {
      await forceDispose();
    }
  }
}

/// Factory function to create a platform-specific worker client.
Future<VerovioWorkerClient> createWorkerClient({
  required String resourcePath,
}) {
  return VerovioWorkerClientIO.connect(resourcePath: resourcePath);
}
