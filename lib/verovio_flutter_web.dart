import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web platform registrant for `verovio_flutter`.
///
/// The actual Verovio functionality is provided entirely through pure-Dart
/// conditional imports (see `verovio_flutter.dart` and `src/worker/*`), so this
/// registrant is intentionally a no-op. It exists only to satisfy the Flutter
/// web plugin registration contract declared in `pubspec.yaml`.
class VerovioFlutterWeb {
  /// Registers the web plugin. No platform channel is used; this is a no-op.
  static void registerWith(Registrar registrar) {
    // No-op: functionality is provided via conditional imports, not channels.
  }
}
