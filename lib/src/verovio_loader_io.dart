import 'dart:ffi';
import 'dart:io';

/// 加载平台特定的 Verovio 原生库（IO 平台：Android / iOS）。
DynamicLibrary loadVerovioLibrary() {
  if (Platform.isAndroid) return DynamicLibrary.open('libverovio_flutter.so');
  if (Platform.isIOS) return DynamicLibrary.process();
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
