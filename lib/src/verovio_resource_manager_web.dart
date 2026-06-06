import 'dart:async';

/// Web platform stub: Verovio assets are embedded in WASM.
///
/// On Web, font data and resources are bundled directly into the WASM module,
/// so no runtime asset copying is needed. This implementation provides a no-op
/// stub that returns a placeholder path to satisfy the API contract.
class VerovioResourceManager {
  VerovioResourceManager._();

  static const String _placeholderPath = '/verovio';

  /// Returns immediately without copying assets (they are built into WASM).
  /// Returns a placeholder path for compatibility with IO platforms.
  static Future<String> ensureVerovioAssetsReady() async {
    return _placeholderPath;
  }
}
