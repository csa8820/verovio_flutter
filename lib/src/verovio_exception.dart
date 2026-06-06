/// Exception thrown when a Verovio call fails.
class VerovioException implements Exception {
  /// Creates an exception for the failed Verovio [method].
  VerovioException({required this.method, this.log = ''});

  /// The Verovio API method that failed.
  final String method;

  /// The native Verovio log captured for the failure.
  final String log;

  /// Returns a readable description of the failure.
  @override
  String toString() => 'VerovioException(method: $method, log: $log)';
}
