import 'package:verovio_flutter/src/verovio_exception.dart';

/// Abstract interface for a Verovio worker client.
///
/// Implementations provide unified communication with a Verovio backend,
/// whether via isolate (IO), Web Worker, or other mechanisms.
abstract base class VerovioWorkerClient {
  /// Sends a raw request to the worker and returns the result.
  ///
  /// [action] is the worker action name; [payload] contains action parameters.
  /// Returns the unpacked 'result' field from the worker response, or throws
  /// [VerovioException] if the response indicates an error.
  Future<Object?> sendRaw(
    String action, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]);

  /// Gracefully disposes the worker.
  ///
  /// Sends a 'dispose' request to allow the worker to clean up,
  /// then releases client resources. Idempotent.
  Future<void> dispose();

  /// Forcefully terminates the worker immediately.
  ///
  /// Kills the worker process without waiting for a dispose response,
  /// and releases all pending completers with an error.
  /// Idempotent.
  Future<void> forceDispose();
}
