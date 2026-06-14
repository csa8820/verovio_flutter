// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:verovio_flutter/src/hit_map/models_data.dart';
import 'package:verovio_flutter/src/hit_map/parser_core.dart';
import 'package:verovio_flutter/src/verovio_exception.dart';
import 'package:verovio_flutter/src/web/verovio_js_interop.dart';
import 'package:verovio_flutter/src/worker/worker_client.dart';

// ============================================================================
// Argument Extraction Helpers (copied from web/verovio_worker.dart)
// ============================================================================

String _stringArg(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String) {
    throw ArgumentError.value(value, key, 'must be a String');
  }
  return value;
}

String _optionalStringArg(Map<String, Object?> payload, String key,
    {String defaultValue = ''}) {
  final value = payload[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! String) {
    throw ArgumentError.value(value, key, 'must be a String');
  }
  return value;
}

int _intArg(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! int) {
    throw ArgumentError.value(value, key, 'must be an int');
  }
  return value;
}

bool _boolArg(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! bool) {
    throw ArgumentError.value(value, key, 'must be a bool');
  }
  return value;
}

ParseConfigData _parseConfigArg(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! Map) {
    throw ArgumentError.value(value, key, 'must be a Map');
  }
  return ParseConfigData.fromJson(value.cast<String, Object?>());
}

// ============================================================================
// Initialization & Lifecycle (copied from web/verovio_worker.dart)
// ============================================================================

Object? _spawn(Map<String, Object?> payload) {
  // Web: toolkit is initialized in VerovioWorkerClientInline.connect().
  // This action is a no-op; the toolkit is already created.
  return null;
}

Object? _setResourcePath(Map<String, Object?> payload) {
  // Web: no-op (fonts are embedded in WASM)
  return true;
}

String _getResourcePath() {
  // Web: fonts are embedded in WASM; no filesystem path exists.
  // Return a stable placeholder so the public API stays consistent with io.
  return '';
}

Object? _disposeToolkit(VerovioToolkit? toolkit) {
  if (toolkit != null) {
    toolkit.destroy();
  }
  return null;
}

// ============================================================================
// C2 Phase: Core Rendering Methods (copied from web/verovio_worker.dart)
// ============================================================================

Object? _setOptionsJson(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final json = _stringArg(payload, 'json');
  toolkit.setOptions(json);
  return null;
}

Object? _loadData(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final data = _stringArg(payload, 'data');
  final success = toolkit.loadData(data);
  if (!success) {
    throw StateError('loadData failed: ${toolkit.getLog()}');
  }
  return null;
}

Object? _loadZipDataBase64(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final data = _stringArg(payload, 'base64Data');
  final success = toolkit.loadZipDataBase64(data);
  if (!success) {
    throw StateError('loadZipDataBase64 failed: ${toolkit.getLog()}');
  }
  return null;
}

Object? _loadZipDataBufferInline(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  // Inline receives Dart Uint8List (not JS Uint8Array like worker does).
  final bytes = payload['bytes'];
  if (bytes is! Uint8List) {
    throw StateError('loadZipDataBuffer: payload must contain Uint8List bytes');
  }
  final jsU8 = bytes.toJS as JSObject;
  final arrayBuffer = jsU8.getProperty<JSObject>('buffer'.toJS);
  final success = toolkit.loadZipDataBuffer(arrayBuffer);
  if (!success) {
    throw StateError('loadZipDataBuffer failed: ${toolkit.getLog()}');
  }
  return true;
}

int _getPageCount(VerovioToolkit toolkit) {
  return toolkit.getPageCount();
}

String _renderToSvg(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final pageNo = _intArg(payload, 'pageNo');
  final xmlDeclaration = _boolArg(payload, 'xmlDeclaration');
  return toolkit.renderToSVG(pageNo, xmlDeclaration ? 1 : 0);
}

String _getLog(VerovioToolkit toolkit) {
  return toolkit.getLog();
}

String _getVersion(VerovioToolkit toolkit) {
  return toolkit.getVersion();
}

// ============================================================================
// D3.1: MIDI Rendering (copied from web/verovio_worker.dart)
// ============================================================================

String _renderToMidi(VerovioToolkit toolkit) {
  return toolkit.renderToMIDI();
}

// ============================================================================
// D3.2: Timemap, PAE, Expansion Map, RenderData (copied from web/verovio_worker.dart)
// ============================================================================

String _renderToTimemap(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final jsonOptions = _optionalStringArg(payload, 'jsonOptions');
  return toolkit.renderToTimemap(jsonOptions);
}

String _renderToPae(VerovioToolkit toolkit) {
  return toolkit.renderToPAE();
}

String _renderToExpansionMap(VerovioToolkit toolkit) {
  return toolkit.renderToExpansionMap();
}

String _renderData(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final data = _stringArg(payload, 'data');
  final jsonOptions = _stringArg(payload, 'jsonOptions');
  return toolkit.renderData(data, jsonOptions);
}

// ============================================================================
// D3.3: MEI & Humdrum Conversions (copied from web/verovio_worker.dart)
// ============================================================================

String _getMei(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final jsonOptions = _stringArg(payload, 'jsonOptions');
  return toolkit.getMEI(jsonOptions);
}

String _getHumdrum(VerovioToolkit toolkit) {
  return toolkit.getHumdrum();
}

String _convertHumdrumToHumdrum(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final data = _stringArg(payload, 'data');
  return toolkit.convertHumdrumToHumdrum(data);
}

String _convertHumdrumToMidi(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final data = _stringArg(payload, 'data');
  return toolkit.convertHumdrumToMIDI(data);
}

String _convertMeiToHumdrum(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final data = _stringArg(payload, 'data');
  return toolkit.convertMEIToHumdrum(data);
}

// ============================================================================
// D3.4: Element Attribute & Timing Queries (copied from web/verovio_worker.dart)
// ============================================================================

String _getElementAttr(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final xmlId = _stringArg(payload, 'xmlId');
  return toolkit.getElementAttr(xmlId);
}

String _getElementsAtTime(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final millisec = _intArg(payload, 'millisec');
  return toolkit.getElementsAtTime(millisec);
}

String _getMidiValuesForElement(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final xmlId = _stringArg(payload, 'xmlId');
  return toolkit.getMIDIValuesForElement(xmlId);
}

String _getTimesForElement(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final xmlId = _stringArg(payload, 'xmlId');
  return toolkit.getTimesForElement(xmlId);
}

String _getNotatedIdForElement(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final xmlId = _stringArg(payload, 'xmlId');
  return toolkit.getNotatedIdForElement(xmlId);
}

String _getExpansionIdsForElement(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final xmlId = _stringArg(payload, 'xmlId');
  return toolkit.getExpansionIdsForElement(xmlId);
}

// ============================================================================
// D3.5: Selection & Editing (copied from web/verovio_worker.dart)
// ============================================================================

bool _select(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final selectionJson = _stringArg(payload, 'selectionJson');
  return toolkit.select(selectionJson);
}

bool _edit(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final editorAction = _stringArg(payload, 'editorAction');
  return toolkit.edit(editorAction);
}

String _editInfo(VerovioToolkit toolkit) {
  return toolkit.editInfo();
}

String _validatePae(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final data = _stringArg(payload, 'data');
  return toolkit.validatePAE(data);
}

// ============================================================================
// D3.6: Scale & Pagination Queries (copied from web/verovio_worker.dart)
// ============================================================================

bool _setScale(Map<String, Object?> payload, VerovioToolkit toolkit) {
  // Web: setScale not exposed in WASM toolkit; no-op
  _intArg(payload, 'scale'); // validate input
  return true;
}

int _getScale(VerovioToolkit toolkit) {
  // Web: getScale not exposed in WASM toolkit; return default
  return 40;
}

int _getPageWithElement(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final xmlId = _stringArg(payload, 'xmlId');
  return toolkit.getPageWithElement(xmlId);
}

int _getTimeForElement(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final xmlId = _stringArg(payload, 'xmlId');
  final time = toolkit.getTimeForElement(xmlId);
  return time.toInt(); // Convert double to int
}

// ============================================================================
// D3.7: Layout & Reset Operations (copied from web/verovio_worker.dart)
// ============================================================================

Object? _redoLayout(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final jsonOptions = _optionalStringArg(payload, 'jsonOptions');
  toolkit.redoLayout(jsonOptions);
  return null;
}

Object? _redoPagePitchPosLayout(VerovioToolkit toolkit) {
  toolkit.redoPagePitchPosLayout();
  return null;
}

Object? _resetOptions(VerovioToolkit toolkit) {
  toolkit.resetOptions();
  return null;
}

Object? _resetXmlIdSeed(Map<String, Object?> payload, VerovioToolkit toolkit) {
  final seed = _intArg(payload, 'seed');
  toolkit.resetXmlIdSeed(seed);
  return null;
}

// ============================================================================
// D3.8: Options & Format Queries (copied from web/verovio_worker.dart)
// ============================================================================

String _getAvailableOptions(VerovioToolkit toolkit) {
  return toolkit.getAvailableOptions();
}

String _getDefaultOptions(VerovioToolkit toolkit) {
  return toolkit.getDefaultOptions();
}

String _getOptions(VerovioToolkit toolkit) {
  return toolkit.getOptions();
}

String _getOptionUsageString(VerovioToolkit toolkit) {
  // Web toolkit may not expose this; return placeholder
  return 'Web toolkit does not expose option usage string';
}

String _getDescriptiveFeatures(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final jsonOptions = _stringArg(payload, 'jsonOptions');
  return toolkit.getDescriptiveFeatures(jsonOptions);
}

String _getId(VerovioToolkit toolkit) {
  // Web toolkit likely doesn't expose ID, return placeholder
  return 'web-toolkit-instance';
}

bool _setInputFrom(Map<String, Object?> payload, VerovioToolkit toolkit) {
  // Web: I/O format setting is not typically exposed; no-op
  return true;
}

bool _setOutputTo(Map<String, Object?> payload, VerovioToolkit toolkit) {
  // Web: I/O format setting is not typically exposed; no-op
  return true;
}

// ============================================================================
// D2 Phase: HitMap Parsing (copied from web/verovio_worker.dart)
// ============================================================================

/// Parse hit map from SVG string (pure Dart parser, no JS involved).
Map<String, Object?> _parseHitMap(Map<String, Object?> payload) {
  final String svg = _stringArg(payload, 'svg');
  final int pageIndex = _intArg(payload, 'pageIndex');
  final ParseConfigData config = _parseConfigArg(payload, 'config');

  final PageHitMapData hitMap = HitMapParserCore.parseSync(
    svg,
    pageIndex: pageIndex,
    config: config,
  );
  return hitMap.toJson();
}

/// Render page to SVG, then parse hit map (JS rendering + Dart parsing).
Map<String, Object?> _renderPageWithHitMap(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  final int pageIndex = _intArg(payload, 'pageIndex');
  final ParseConfigData config = _parseConfigArg(payload, 'config');

  // Render SVG via toolkit (JS)
  final String svg = toolkit.renderToSVG(pageIndex, 1); // xmlDeclaration = true

  // Parse hit map via Dart parser (web version)
  final PageHitMapData hitMap = HitMapParserCore.parseSync(
    svg,
    pageIndex: pageIndex,
    config: config,
  );

  return <String, Object?>{
    'svg': svg,
    'hitMap': hitMap.toJson(),
  };
}

// ============================================================================
// Inline Worker Client Implementation
// ============================================================================

/// Inline (non-Worker) implementation of [VerovioWorkerClient] for WeChat mini-app.
///
/// Holds a [VerovioToolkit] instance directly in the logic layer and executes
/// actions synchronously. No Worker thread or transferable messages.
final class VerovioWorkerClientInline extends VerovioWorkerClient {
  VerovioWorkerClientInline._(this._toolkit);

  VerovioToolkit? _toolkit;
  bool _disposed = false;

  /// Initialize the inline client from the global verovio module.
  ///
  /// The WeChat mini-app bootstrap has already required verovio-weapp.js,
  /// making the global `verovio` object available. This method waits for the
  /// emscripten runtime to be ready, then creates a toolkit instance.
  static Future<VerovioWorkerClientInline> connect({
    required String resourcePath,
  }) async {
    // 微信侧 verovio 走分包异步加载，全局 verovio 可能尚未注入，轮询等待。
    await _waitForGlobalVerovio(const Duration(seconds: 30));
    await waitForRuntimeReady().timeout(const Duration(seconds: 30));
    final toolkit = VerovioToolkit.create(verovioModule!);
    return VerovioWorkerClientInline._(toolkit);
  }

  static Future<void> _waitForGlobalVerovio(Duration timeout) async {
    if (verovioModule != null) return;
    final deadline = DateTime.now().add(timeout);
    while (verovioModule == null) {
      if (DateTime.now().isAfter(deadline)) {
        throw VerovioException(
          method: 'worker-init',
          log: '等待全局 verovio 超时：请确认小程序已通过分包 bootstrap 注入 self.verovio。',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  Future<Object?> sendRaw(String action,
      [Map<String, Object?> payload = const <String, Object?>{}]) async {
    if (_disposed) {
      throw StateError('VerovioAsyncService has been disposed');
    }

    // Logic layer is single-threaded: yield one event loop iteration to
    // mitigate UI stalling on heavy operations (loadData, render*).
    // This is not a complete fix but helps with scheduling.
    await Future<void>.delayed(Duration.zero);

    try {
      return _dispatch(action, payload);
    } on VerovioException {
      rethrow;
    } catch (e) {
      throw VerovioException(method: action, log: e.toString());
    }
  }

  /// Dispatch action to the appropriate handler.
  ///
  /// Similar to web/verovio_worker.dart's _dispatch, but reads from the
  /// instance _toolkit field instead of a global. Includes all ~50 actions.
  Object? _dispatch(String action, Map<String, Object?> payload) {
    final toolkit = _toolkit;
    if (toolkit == null &&
        action != 'setResourcePath' &&
        action != 'spawn') {
      throw StateError('Toolkit not initialized');
    }

    return switch (action) {
      // Initialization & lifecycle
      'spawn' => _spawn(payload),
      'setResourcePath' => _setResourcePath(payload),
      'getResourcePath' => _getResourcePath(),

      // Core rendering (C2 phase)
      'setOptionsJson' => _setOptionsJson(payload, toolkit!),
      'loadData' => _loadData(payload, toolkit!),
      'loadZipDataBase64' => _loadZipDataBase64(payload, toolkit!),
      'loadZipDataBuffer' => _loadZipDataBufferInline(payload, toolkit!),
      'getPageCount' => _getPageCount(toolkit!),
      'renderToSvg' => _renderToSvg(payload, toolkit!),
      'getLog' => _getLog(toolkit!),
      'getVersion' => _getVersion(toolkit!),

      // D2 phase: hit_map parsing
      'parseHitMap' => _parseHitMap(payload),
      'renderPageWithHitMap' => _renderPageWithHitMap(payload, toolkit!),

      // D3.1: MIDI rendering
      'renderToMidi' => _renderToMidi(toolkit!),

      // D3.2: timemap & expansion & PAE
      'renderToTimemap' => _renderToTimemap(payload, toolkit!),
      'renderToPae' => _renderToPae(toolkit!),
      'renderToExpansionMap' => _renderToExpansionMap(toolkit!),
      'renderData' => _renderData(payload, toolkit!),

      // D3.3: MEI & Humdrum conversions
      'getMei' => _getMei(payload, toolkit!),
      'getHumdrum' => _getHumdrum(toolkit!),
      'convertHumdrumToHumdrum' =>
        _convertHumdrumToHumdrum(payload, toolkit!),
      'convertHumdrumToMidi' =>
        _convertHumdrumToMidi(payload, toolkit!),
      'convertMeiToHumdrum' =>
        _convertMeiToHumdrum(payload, toolkit!),

      // D3.4: Element attribute & timing queries
      'getElementAttr' => _getElementAttr(payload, toolkit!),
      'getElementsAtTime' => _getElementsAtTime(payload, toolkit!),
      'getMidiValuesForElement' =>
        _getMidiValuesForElement(payload, toolkit!),
      'getTimesForElement' => _getTimesForElement(payload, toolkit!),
      'getNotatedIdForElement' =>
        _getNotatedIdForElement(payload, toolkit!),
      'getExpansionIdsForElement' =>
        _getExpansionIdsForElement(payload, toolkit!),

      // D3.5: Selection & editing
      'select' => _select(payload, toolkit!),
      'edit' => _edit(payload, toolkit!),
      'editInfo' => _editInfo(toolkit!),
      'validatePae' => _validatePae(payload, toolkit!),

      // D3.6: Scale & pagination queries
      'setScale' => _setScale(payload, toolkit!),
      'getScale' => _getScale(toolkit!),
      'getPageWithElement' => _getPageWithElement(payload, toolkit!),
      'getTimeForElement' => _getTimeForElement(payload, toolkit!),

      // D3.7: Layout & reset operations
      'redoLayout' => _redoLayout(payload, toolkit!),
      'redoPagePitchPosLayout' => _redoPagePitchPosLayout(toolkit!),
      'resetOptions' => _resetOptions(toolkit!),
      'resetXmlIdSeed' => _resetXmlIdSeed(payload, toolkit!),

      // D3.8: Options queries & I/O format
      'getAvailableOptions' => _getAvailableOptions(toolkit!),
      'getDefaultOptions' => _getDefaultOptions(toolkit!),
      'getOptions' => _getOptions(toolkit!),
      'getOptionUsageString' => _getOptionUsageString(toolkit!),
      'getDescriptiveFeatures' =>
        _getDescriptiveFeatures(payload, toolkit!),
      'getId' => _getId(toolkit!),
      'setInputFrom' => _setInputFrom(payload, toolkit!),
      'setOutputTo' => _setOutputTo(payload, toolkit!),

      // Lifecycle
      'dispose' => _disposeToolkit(_toolkit),

      _ => throw UnimplementedError('Action $action not yet implemented'),
    };
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    try {
      _toolkit?.destroy();
    } finally {
      _toolkit = null;
      _disposed = true;
    }
  }

  @override
  Future<void> forceDispose() async {
    _toolkit = null;
    _disposed = true;
  }
}
