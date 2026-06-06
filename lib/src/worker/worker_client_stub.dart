import 'package:verovio_flutter/src/worker/worker_client.dart';

/// Stub (unsupported) implementation of [VerovioWorkerClient].
///
/// Used on platforms where the Verovio worker is not yet implemented.
final class VerovioWorkerClientStub extends VerovioWorkerClient {
  @override
  Future<Object?> sendRaw(
    String action, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) {
    throw UnsupportedError(
      'Verovio worker is not supported on this platform',
    );
  }

  @override
  Future<void> dispose() {
    throw UnsupportedError(
      'Verovio worker is not supported on this platform',
    );
  }

  @override
  Future<void> forceDispose() {
    throw UnsupportedError(
      'Verovio worker is not supported on this platform',
    );
  }
}

/// Factory function to create a platform-specific worker client.
///
/// On unsupported platforms, this always throws [UnsupportedError].
Future<VerovioWorkerClient> createWorkerClient({
  required String resourcePath,
}) async {
  throw UnsupportedError(
    'Verovio worker is not supported on this platform',
  );
}
