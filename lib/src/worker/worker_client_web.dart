import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:verovio_flutter/src/verovio_exception.dart';
import 'package:verovio_flutter/src/worker/worker_client.dart';

// ============================================================================
// Web Worker Bindings
// ============================================================================

/// Type for Web Worker (from main thread perspective).
extension type VerovioWorker(JSObject _) implements JSObject {
  /// Set the onmessage event handler.
  external set onmessage(JSFunction? handler);

  /// Set the onerror event handler (for worker errors and exceptions).
  external set onerror(JSFunction? handler);

  /// Set the onmessageerror event handler (for message deserialization errors).
  external set onmessageerror(JSFunction? handler);

  /// Send a message to the worker (accepts both strings and objects).
  external void postMessage(JSAny message);

  /// Terminate the worker immediately.
  external void terminate();
}

/// The global `Worker` constructor.
@JS('Worker')
external JSFunction get _workerConstructor;

/// Create a new Web Worker from the given script URL.
///
/// Self-contained: spawns the worker directly via `new Worker(...)` so the
/// package does not require any external bootstrap script (e.g. the old
/// verovio_init.js helper) to be loaded by the host page.
VerovioWorker createWorker(String scriptUrl) {
  final worker =
      _workerConstructor.callAsConstructorVarArgs<JSObject>(<JSAny?>[
    scriptUrl.toJS,
  ]);
  return worker as VerovioWorker;
}

/// Optional runtime configuration set by the host page, e.g.:
/// `window.verovioFlutterConfig = { workerUrl: '...', wasmUrl: '...' };`
@JS('verovioFlutterConfig')
external JSObject? get _verovioFlutterConfig;

/// Read a non-empty string field from the optional config object.
String? _readConfigString(JSObject? obj, String key) {
  if (obj == null) {
    return null;
  }
  final value = obj.getProperty<JSAny?>(key.toJS);
  if (value != null && value.typeofEquals('string')) {
    final str = (value as JSString).toDart;
    return str.isNotEmpty ? str : null;
  }
  return null;
}

/// Create a JS object containing a binary message (not JSON-serializable).
JSObject _createBinaryMessage(
    int requestId, String action, JSObject uint8array, int byteLength) {
  final payload = JSObject();
  payload.setProperty('bytesSize'.toJS, byteLength.toJS);
  payload.setProperty('bytes'.toJS, uint8array);

  final message = JSObject();
  message.setProperty('requestId'.toJS, requestId.toJS);
  message.setProperty('action'.toJS, action.toJS);
  message.setProperty('payload'.toJS, payload);
  return message;
}

/// Extract the underlying ArrayBuffer from a Uint8Array.
JSObject _getArrayBuffer(JSObject uint8array) =>
    uint8array.getProperty<JSObject>('buffer'.toJS);

/// Post a message with a transferable list to the worker (zero-copy).
void _postMessageWithTransfer(
    JSObject worker, JSObject message, JSObject buffer) {
  worker.callMethodVarArgs<JSAny?>('postMessage'.toJS, <JSAny?>[
    message,
    <JSAny?>[buffer].toJS,
  ]);
}

// ============================================================================
// Web Implementation of VerovioWorkerClient
// ============================================================================

/// Web (Worker-based) implementation of [VerovioWorkerClient].
final class VerovioWorkerClientWeb extends VerovioWorkerClient {
  VerovioWorkerClientWeb._(this._worker) {
    // Register message handler (initialized in _waitForReady)
  }

  void _registerMessageHandler() {
    _worker.onmessage = _createMessageHandler();
  }

  JSFunction _createMessageHandler() {
    return ((JSObject event) {
      _handleMessage(event);
    }).toJS;
  }

  void _registerErrorHandlers() {
    // Handle worker errors (uncaught exceptions, runtime errors)
    _worker.onerror = ((JSObject event) {
      _handleWorkerError(event);
    }).toJS;

    // Handle message deserialization errors
    _worker.onmessageerror = ((JSObject event) {
      _handleWorkerMessageError(event);
    }).toJS;
  }

  void _handleWorkerError(JSObject event) {
    // Worker has crashed or thrown an uncaught exception
    if (_disposed) {
      return;
    }
    _disposeInternal(
      VerovioException(
        method: 'worker',
        log: 'Web Worker crashed or threw an uncaught exception',
      ),
    );
  }

  void _handleWorkerMessageError(JSObject event) {
    // Message deserialization failed (e.g., circular reference in structured clone)
    if (_disposed) {
      return;
    }
    _disposeInternal(
      VerovioException(
        method: 'worker',
        log: 'Web Worker message deserialization error',
      ),
    );
  }

  /// Internal dispose helper that completes pending futures with an error.
  void _disposeInternal(Object error) {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
    _worker.terminate();
  }

  final VerovioWorker _worker;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  int _nextRequestId = 0;
  bool _disposed = false;

  /// Spawns a Web Worker and creates a web client.
  static Future<VerovioWorkerClientWeb> connect({
    required String resourcePath,
  }) async {
    // Build the worker script URL. The WASM toolkit location is passed to the
    // worker via the `wasm` query parameter so the worker can importScripts it.
    // Both URLs are configurable through `window.verovioFlutterConfig`.
    final workerUrl = _getWorkerUrl();
    final wasmUrl = _getWasmUrl();
    final spawnUrl = '$workerUrl?wasm=${Uri.encodeComponent(wasmUrl)}';

    // Create the worker
    final worker = createWorker(spawnUrl);

    // Create client instance
    final client = VerovioWorkerClientWeb._(worker);

    // Wait for ready signal (also fails fast on worker init errors)
    try {
      await client._waitForReady();

      // Send initialization (spawn action)
      await client.sendRaw('spawn', <String, Object?>{
        'resourcePath': resourcePath,
      });

      return client;
    } catch (_) {
      await client.forceDispose();
      rethrow;
    }
  }

  /// Determine the URL for the worker script.
  ///
  /// Defaults to 'verovio_worker.dart.js' at the web root, overridable via
  /// `window.verovioFlutterConfig.workerUrl`.
  static String _getWorkerUrl() {
    return _readConfigString(_verovioFlutterConfig, 'workerUrl') ??
        'verovio_worker.dart.js';
  }

  /// Determine the URL for the Verovio WASM toolkit script.
  ///
  /// Defaults to 'verovio/verovio-toolkit-wasm.js' (resolved relative to the
  /// worker), overridable via `window.verovioFlutterConfig.wasmUrl`.
  static String _getWasmUrl() {
    return _readConfigString(_verovioFlutterConfig, 'wasmUrl') ??
        'verovio/verovio-toolkit-wasm.js';
  }

  /// Wait for the ready signal from the worker.
  ///
  /// Resolves when the worker posts `{ready: true}`. Fails fast (instead of
  /// waiting out the timeout) when the worker reports an initialization error
  /// via `{error: ...}` or crashes during startup.
  Future<void> _waitForReady() {
    final completer = Completer<void>();

    void fail(Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    // Temporarily handle ready/error messages during initialization.
    _worker.onmessage = ((JSObject event) {
      try {
        final msgStr = _getMessageData(event);
        if (msgStr == null || msgStr.isEmpty || msgStr == 'null') {
          return;
        }
        final message = jsonDecode(msgStr) as Object?;
        if (message is! Map) {
          return;
        }
        if (message['ready'] == true) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        } else if (message['error'] != null) {
          fail(VerovioException(
            method: 'worker-init',
            log: message['error'].toString(),
          ));
        }
      } catch (_) {
        // Ignore malformed ready messages
      }
    }).toJS;

    // Fail fast if the worker script itself fails to load or throws.
    _worker.onerror = ((JSObject event) {
      fail(VerovioException(
        method: 'worker-init',
        log: 'Web Worker failed to load or threw during initialization. '
            'Ensure verovio_worker.dart.js and the Verovio WASM toolkit '
            '(verovio/verovio-toolkit-wasm.js) are reachable at the web root.',
      ));
    }).toJS;

    // Set a timeout for the ready signal.
    final timeout = Timer(const Duration(seconds: 30), () {
      fail(TimeoutException(
        'Web Worker failed to initialize within 30 seconds',
      ));
    });

    return completer.future.whenComplete(() {
      timeout.cancel();
    }).then((_) {
      // Switch to the steady-state message and error handlers.
      _registerMessageHandler();
      _registerErrorHandlers();
    });
  }

  /// Handle incoming messages from the worker.
  void _handleMessage(JSObject event) {
    try {
      final msgStr = _getMessageData(event);
      if (msgStr == null || msgStr.isEmpty || msgStr == 'null') {
        return;
      }

      final message = jsonDecode(msgStr) as Object?;
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
    } catch (_) {
      // Ignore malformed messages
    }
  }

  @override
  Future<Object?> sendRaw(String action,
      [Map<String, Object?> payload = const <String, Object?>{}]) async {
    if (_disposed) {
      throw StateError('VerovioAsyncService has been disposed');
    }

    // Check if this is a binary operation that needs transferable
    if (action == 'loadZipDataBuffer' && payload['bytes'] is Uint8List) {
      return _sendRawBinary(action, payload);
    }

    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[requestId] = completer;

    try {
      final request = jsonEncode({
        'requestId': requestId,
        'action': action,
        'payload': payload,
      });
      _postMessage(request);

      final response = await completer.future;
      if (response['ok'] == true) {
        return response['result'];
      }

      throw VerovioException(
        method: action,
        log: response['error']?.toString() ?? '',
      );
    } catch (e) {
      _pending.remove(requestId);
      if (e is VerovioException) {
        rethrow;
      }
      rethrow;
    }
  }

  /// Send binary data using transferable (zero-copy for large buffers).
  Future<Object?> _sendRawBinary(
    String action,
    Map<String, Object?> payload,
  ) async {
    if (_disposed) {
      throw StateError('VerovioAsyncService has been disposed');
    }

    final bytes = payload['bytes'] as Uint8List;
    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[requestId] = completer;

    try {
      // Convert Uint8List to JSUint8Array
      final jsUint8Array = bytes.toJS as JSObject;

      // Create a JS object with the request data and binary payload
      final message = _createBinaryMessage(
        requestId,
        action,
        jsUint8Array,
        bytes.length,
      );

      // Extract the underlying ArrayBuffer for transfer
      final arrayBuffer = _getArrayBuffer(jsUint8Array);

      // Post message with transferable (transfers ownership to worker)
      _postMessageWithTransfer(_worker._, message, arrayBuffer);

      final response = await completer.future;
      if (response['ok'] == true) {
        return response['result'];
      }

      throw VerovioException(
        method: action,
        log: response['error']?.toString() ?? '',
      );
    } catch (e) {
      _pending.remove(requestId);
      if (e is VerovioException) {
        rethrow;
      }
      rethrow;
    }
  }


  @override
  Future<void> forceDispose() async {
    _disposeInternal(StateError('VerovioAsyncService has been disposed'));
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

  /// Helper to post a message (use native postMessage).
  void _postMessage(String msg) {
    _worker.postMessage(msg.toJS);
  }

  /// Extract `event.data` as a JSON string, or null if it is not a string.
  static String? _getMessageData(JSObject event) {
    final data = event.getProperty<JSAny?>('data'.toJS);
    if (data == null || !data.typeofEquals('string')) {
      return null;
    }
    return (data as JSString).toDart;
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/// Factory function to create a Web worker client.
Future<VerovioWorkerClient> createWorkerClient({
  required String resourcePath,
}) {
  return VerovioWorkerClientWeb.connect(resourcePath: resourcePath);
}
