/// Stub implementation of VerovioService for unsupported platforms (e.g., Web).
///
/// Web platform does not support native FFI. Use [VerovioAsyncService] instead.
base class VerovioService {
  /// This constructor is not available on Web.
  VerovioService._() {
    throw UnsupportedError(
        'VerovioService requires native FFI, which is not available on Web. '
        'Use VerovioAsyncService instead.');
  }

  /// Not available on Web.
  static Future<VerovioService> spawn({required String resourcePath}) {
    throw UnsupportedError(
        'VerovioService requires native FFI, which is not available on Web. '
        'Use VerovioAsyncService instead.');
  }
}
