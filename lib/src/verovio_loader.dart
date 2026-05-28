import 'dart:ffi';
import 'dart:io';

/// Loads the platform-specific Verovio native library.
DynamicLibrary loadVerovioLibrary() {
  if (Platform.isAndroid) return DynamicLibrary.open('libverovio_flutter.so');
  if (Platform.isIOS) return DynamicLibrary.process();
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
