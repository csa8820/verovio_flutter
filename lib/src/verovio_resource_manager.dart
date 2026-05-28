import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Manages copying Verovio assets into the app support directory.
class VerovioResourceManager {
  VerovioResourceManager._();

  static const String _assetsPrefix =
      'packages/verovio_flutter/assets/verovio_data/';
  static const String _versionAssetPath = 'native/VEROVIO_VERSION';
  static const String _versionFileName = 'VERSION';
  static const List<String> _requiredAssetPaths = <String>[
    'Bravura.xml',
    'Gootville.xml',
    'Leipzig.xml',
    'Leland.xml',
    'Petaluma.xml',
    'text/Times.xml',
    'text/Times-bold.xml',
    'text/Times-bold-italic.xml',
    'text/Times-italic.xml',
  ];

  static Future<String>? _inFlight;

  /// Ensures the bundled Verovio assets are available on disk.
  static Future<String> ensureVerovioAssetsReady() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _ensureVerovioAssetsReadyImpl();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  static Future<String> _ensureVerovioAssetsReadyImpl() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final targetDirectory = Directory(
        _joinPath(supportDirectory.path, 'verovio_data'),
      );
      final targetVersionFile = File(
        _joinPath(targetDirectory.path, _versionFileName),
      );
      final version = await _loadVersion();

      if (await _isVersionCurrent(targetVersionFile, version)) {
        return targetDirectory.path;
      }

      if (await targetDirectory.exists()) {
        await targetDirectory.delete(recursive: true);
      }
      await targetDirectory.create(recursive: true);

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assetPaths = manifest
          .listAssets()
          .where((path) => path.startsWith(_assetsPrefix))
          .toList()
        ..sort();

      final missingAssets = _requiredAssetPaths
          .map((relativePath) => '$_assetsPrefix$relativePath')
          .where((path) => !assetPaths.contains(path))
          .toList();
      if (missingAssets.isNotEmpty) {
        throw StateError(
          'Verovio asset manifest is incomplete. Missing required assets: '
          '${missingAssets.join(', ')}',
        );
      }

      for (final assetPath in assetPaths) {
        final relativePath = assetPath.substring(_assetsPrefix.length);
        final outputFile = File(
          _joinPath(targetDirectory.path, relativePath),
        );
        await outputFile.parent.create(recursive: true);
        final bytes = await rootBundle.load(assetPath);
        await outputFile.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
      }

      await targetVersionFile.parent.create(recursive: true);
      await targetVersionFile.writeAsString(version, flush: true);

      debugPrint('Verovio assets copied to ${targetDirectory.path}');
      return targetDirectory.path;
    } catch (error, stackTrace) {
      throw StateError(
        'ensureVerovioAssetsReady failed: $error\n$stackTrace',
      );
    }
  }

  static Future<String> _loadVersion() async {
    try {
      final version = await rootBundle.loadString(_versionAssetPath);
      final trimmed = version.trim();
      if (trimmed.isEmpty) {
        throw StateError('$_versionAssetPath is empty');
      }
      return trimmed;
    } on FlutterError catch (_) {
      return 'dev-snapshot';
    }
  }

  static Future<bool> _isVersionCurrent(
      File targetVersionFile, String version) async {
    if (!await targetVersionFile.exists()) {
      return false;
    }

    final existingVersion = await targetVersionFile.readAsString();
    return existingVersion.trim() == version.trim();
  }

  static String _joinPath(String left, String right) {
    if (left.isEmpty) {
      return right;
    }
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }
}
