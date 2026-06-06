// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:verovio_flutter/src/hit_map/models_data.dart';
import 'package:verovio_flutter/src/hit_map/parser_core.dart';
import 'package:verovio_flutter/src/web/verovio_js_interop.dart';

// ============================================================================
// Bindings to DedicatedWorkerGlobalScope (self in worker context)
// ============================================================================

/// Type for DedicatedWorkerGlobalScope (the 'self' object in a Web Worker).
extension type DedicatedWorkerGlobalScope(JSObject _) implements JSObject {
  /// Set callback for incoming messages from the main thread.
  external set onmessage(JSFunction? handler);

  /// Send a message to the main thread.
  /// Message is automatically structured-cloned by the browser.
  /// Accepts strings and objects (JSAny), matching the DOM postMessage API.
  external void postMessage(JSAny message);

  /// The worker's location (used to read the query string).
  external WorkerLocation get location;
}

/// Minimal binding to the worker's WorkerLocation.
extension type WorkerLocation(JSObject _) implements JSObject {
  /// The query string portion of the worker URL (e.g. "?wasm=...").
  external String get search;
}

/// Access the global 'self' object in Web Worker context.
@JS('self')
external DedicatedWorkerGlobalScope get workerGlobalScope;

/// Synchronously import an external script into the worker scope.
///
/// Used to load `verovio-toolkit-wasm.js`, which defines the global `verovio`
/// module that the js_interop bindings rely on. Without this the module is
/// never present in the worker and initialization fails.
@JS('importScripts')
external void _importScripts(String url);

/// Read the worker's location query string (e.g. "?wasm=...").
String _locationSearch() => workerGlobalScope.location.search;

/// Default URL (resolved relative to the worker script) for the WASM toolkit.
const String _defaultWasmUrl = 'verovio/verovio-toolkit-wasm.js';

/// Resolve the Verovio WASM toolkit URL.
///
/// The main thread may pass an override via the `wasm` query parameter when
/// spawning the worker; otherwise the default sibling path is used.
String _resolveWasmUrl() {
  final search = _locationSearch();
  if (search.isEmpty) {
    return _defaultWasmUrl;
  }
  final query = search.startsWith('?') ? search.substring(1) : search;
  for (final pair in query.split('&')) {
    final idx = pair.indexOf('=');
    if (idx <= 0) {
      continue;
    }
    if (pair.substring(0, idx) == 'wasm') {
      final value = Uri.decodeComponent(pair.substring(idx + 1));
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return _defaultWasmUrl;
}

// ============================================================================
// Global State
// ============================================================================

VerovioToolkit? _toolkit;

// ============================================================================
// Message Protocol
// ============================================================================

class _WorkerRequest {
  _WorkerRequest({
    required this.requestId,
    required this.action,
    required this.payload,
  });

  final int requestId;
  final String action;
  final Map<String, Object?> payload;

  static _WorkerRequest? fromJson(Map<String, Object?> json) {
    final requestId = json['requestId'];
    final action = json['action'];
    final payload = json['payload'];
    if (requestId is! int || action is! String || payload is! Map) {
      return null;
    }
    return _WorkerRequest(
      requestId: requestId,
      action: action,
      payload: payload.cast<String, Object?>(),
    );
  }
}

/// Send response back to main thread.
void _sendResponse({
  required int requestId,
  required bool ok,
  Object? result,
  Object? error,
}) {
  final response = jsonEncode({
    'requestId': requestId,
    'ok': ok,
    if (ok) 'result': result else 'error': error,
  });
  _postMessage(response);
}

/// Send ready signal to main thread.
void _sendReady() {
  final readyMsg = jsonEncode({'ready': true});
  _postMessage(readyMsg);
}

/// Helper to post a string message to the main thread.
void _postMessage(String msg) {
  workerGlobalScope.postMessage(msg.toJS);
}

// ============================================================================
// Toolkit Initialization
// ============================================================================

Future<void> _initializeToolkit() async {
  try {
    // Load the Verovio WASM toolkit into the worker scope. This defines the
    // global `verovio` module that the js_interop bindings depend on.
    // importScripts is synchronous; emscripten then initializes the runtime
    // asynchronously, which waitForRuntimeReady() awaits below.
    if (verovioModule == null) {
      _importScripts(_resolveWasmUrl());
    }

    // Wait for WASM module to be initialized.
    await waitForRuntimeReady();

    // Create toolkit instance.
    final module = verovioModule;
    if (module == null) {
      throw StateError('Verovio module not initialized');
    }
    _toolkit = VerovioToolkit.create(module);

    // Signal ready to main thread.
    _sendReady();
  } catch (error, stackTrace) {
    final errorMsg = jsonEncode({
      'error': 'Toolkit initialization failed: $error\n$stackTrace',
    });
    _postMessage(errorMsg);
  }
}

// ============================================================================
// Argument Extraction Helpers
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
// Action Dispatch (C2 Phase: Basic Rendering + D3 Phase: Extended Methods)
// ============================================================================

Object? _dispatch(_WorkerRequest request) {
  final toolkit = _toolkit;
  if (toolkit == null &&
      request.action != 'setResourcePath' &&
      request.action != 'spawn') {
    throw StateError('Toolkit not initialized');
  }

  return switch (request.action) {
    // Initialization & lifecycle
    'spawn' => _spawn(request.payload),
    'setResourcePath' => _setResourcePath(request.payload),
    'getResourcePath' => _getResourcePath(),

    // Core rendering (C2 phase)
    'setOptionsJson' => _setOptionsJson(request.payload, toolkit!),
    'loadData' => _loadData(request.payload, toolkit!),
    'loadZipDataBase64' => _loadZipDataBase64(request.payload, toolkit!),
    'loadZipDataBuffer' => _loadZipDataBuffer(request.payload, toolkit!),
    'getPageCount' => _getPageCount(toolkit!),
    'renderToSvg' => _renderToSvg(request.payload, toolkit!),
    'getLog' => _getLog(toolkit!),
    'getVersion' => _getVersion(toolkit!),

    // D2 phase: hit_map parsing
    'parseHitMap' => _parseHitMap(request.payload),
    'renderPageWithHitMap' => _renderPageWithHitMap(request.payload, toolkit!),

    // D3.1: MIDI rendering
    'renderToMidi' => _renderToMidi(toolkit!),

    // D3.2: timemap & expansion & PAE
    'renderToTimemap' =>
      _renderToTimemap(request.payload, toolkit!),
    'renderToPae' => _renderToPae(toolkit!),
    'renderToExpansionMap' => _renderToExpansionMap(toolkit!),
    'renderData' => _renderData(request.payload, toolkit!),

    // D3.3: MEI & Humdrum conversions
    'getMei' => _getMei(request.payload, toolkit!),
    'getHumdrum' => _getHumdrum(toolkit!),
    'convertHumdrumToHumdrum' =>
      _convertHumdrumToHumdrum(request.payload, toolkit!),
    'convertHumdrumToMidi' =>
      _convertHumdrumToMidi(request.payload, toolkit!),
    'convertMeiToHumdrum' =>
      _convertMeiToHumdrum(request.payload, toolkit!),

    // D3.4: Element attribute & timing queries
    'getElementAttr' => _getElementAttr(request.payload, toolkit!),
    'getElementsAtTime' => _getElementsAtTime(request.payload, toolkit!),
    'getMidiValuesForElement' =>
      _getMidiValuesForElement(request.payload, toolkit!),
    'getTimesForElement' => _getTimesForElement(request.payload, toolkit!),
    'getNotatedIdForElement' =>
      _getNotatedIdForElement(request.payload, toolkit!),
    'getExpansionIdsForElement' =>
      _getExpansionIdsForElement(request.payload, toolkit!),

    // D3.5: Selection & editing
    'select' => _select(request.payload, toolkit!),
    'edit' => _edit(request.payload, toolkit!),
    'editInfo' => _editInfo(toolkit!),
    'validatePae' => _validatePae(request.payload, toolkit!),

    // D3.6: Scale & pagination queries
    'setScale' => _setScale(request.payload, toolkit!),
    'getScale' => _getScale(toolkit!),
    'getPageWithElement' => _getPageWithElement(request.payload, toolkit!),
    'getTimeForElement' => _getTimeForElement(request.payload, toolkit!),

    // D3.7: Layout & reset operations
    'redoLayout' => _redoLayout(request.payload, toolkit!),
    'redoPagePitchPosLayout' => _redoPagePitchPosLayout(toolkit!),
    'resetOptions' => _resetOptions(toolkit!),
    'resetXmlIdSeed' => _resetXmlIdSeed(request.payload, toolkit!),

    // D3.8: Options queries & I/O format (no-op or placeholder)
    'getAvailableOptions' => _getAvailableOptions(toolkit!),
    'getDefaultOptions' => _getDefaultOptions(toolkit!),
    'getOptions' => _getOptions(toolkit!),
    'getOptionUsageString' => _getOptionUsageString(toolkit!),
    'getDescriptiveFeatures' =>
      _getDescriptiveFeatures(request.payload, toolkit!),
    'getId' => _getId(toolkit!),
    'setInputFrom' => _setInputFrom(request.payload, toolkit!),
    'setOutputTo' => _setOutputTo(request.payload, toolkit!),

    // Lifecycle
    'dispose' => _dispose(toolkit),

    _ => throw UnimplementedError('Action ${request.action} not yet implemented'),
  };
}

// ============================================================================
// Initialization & Lifecycle
// ============================================================================

Object? _spawn(Map<String, Object?> payload) {
  // Web: toolkit is initialized in _initializeToolkit().
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

Object? _dispose(VerovioToolkit? toolkit) {
  if (toolkit != null) {
    toolkit.destroy();
    _toolkit = null;
  }
  return null;
}

// ============================================================================
// C2 Phase: Core Rendering Methods
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

Object? _loadZipDataBuffer(
  Map<String, Object?> payload,
  VerovioToolkit toolkit,
) {
  // The transferred bytes arrive as a Uint8Array; the toolkit wrapper needs
  // its underlying ArrayBuffer.
  final bytes = payload['bytes'] as JSObject?;
  if (bytes == null) {
    throw StateError('loadZipDataBuffer: payload must contain bytes');
  }

  final arrayBuffer = bytes.getProperty<JSObject>('buffer'.toJS);
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
// D3.1: MIDI Rendering
// ============================================================================

String _renderToMidi(VerovioToolkit toolkit) {
  return toolkit.renderToMIDI();
}

// ============================================================================
// D3.2: Timemap, PAE, Expansion Map, RenderData
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
// D3.3: MEI & Humdrum Conversions
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
// D3.4: Element Attribute & Timing Queries
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
// D3.5: Selection & Editing
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
// D3.6: Scale & Pagination Queries
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
// D3.7: Layout & Reset Operations
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
// D3.8: Options & Format Queries (No-op or Placeholder for Web)
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
// D2 Phase: HitMap Parsing
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
// Message Handler
// ============================================================================

void _handleMessage(JSObject event) {
  try {
    // Decode message from event.data
    final msgDataJS = _getMessageData(event);
    if (msgDataJS == null) {
      return;
    }

    // Try to handle as JS object first (for binary messages)
    if (_isBinaryMessage(msgDataJS)) {
      _handleBinaryMessage(msgDataJS as JSObject);
      return;
    }

    // Otherwise, handle as a JSON string message.
    if (!msgDataJS.typeofEquals('string')) {
      return;
    }
    final msgData = (msgDataJS as JSString).toDart;
    if (msgData.isEmpty || msgData == 'null') {
      return;
    }

    final message = jsonDecode(msgData) as Object?;
    if (message is! Map) {
      return;
    }

    final request = _WorkerRequest.fromJson(message.cast<String, Object?>());
    if (request == null) {
      return;
    }

    try {
      final result = _dispatch(request);
      _sendResponse(
        requestId: request.requestId,
        ok: true,
        result: result,
      );
    } catch (error, stackTrace) {
      final toolkit = _toolkit;
      final errorMsg = toolkit != null
          ? '${toolkit.getLog()}\n$error\n$stackTrace'
          : '$error\n$stackTrace';
      _sendResponse(
        requestId: request.requestId,
        ok: false,
        error: errorMsg,
      );
    }
  } catch (_) {
    // Ignore malformed messages
  }
}

/// Check if message is a binary request (JS object with requestId, not a
/// JSON string). String messages arrive as JS strings and are handled as JSON.
bool _isBinaryMessage(JSAny msg) {
  return msg.typeofEquals('object') && (msg as JSObject).has('requestId');
}

/// Handle binary message containing transferred ArrayBuffer
void _handleBinaryMessage(JSObject msg) {
  try {
    // Extract fields from JS object (typed access via js_interop).
    final requestIdJs = msg.getProperty<JSNumber?>('requestId'.toJS);
    final actionJs = msg.getProperty<JSString?>('action'.toJS);
    final payloadObj = msg.getProperty<JSObject?>('payload'.toJS);

    if (requestIdJs == null || actionJs == null || payloadObj == null) {
      return;
    }

    // Convert to _WorkerRequest
    final payload = _jsObjectToMap(payloadObj);

    final request = _WorkerRequest(
      requestId: requestIdJs.toDartInt,
      action: actionJs.toDart,
      payload: payload,
    );

    try {
      final result = _dispatch(request);
      _sendResponse(
        requestId: request.requestId,
        ok: true,
        result: result,
      );
    } catch (error, stackTrace) {
      final toolkit = _toolkit;
      final errorMsg = toolkit != null
          ? '${toolkit.getLog()}\n$error\n$stackTrace'
          : '$error\n$stackTrace';
      _sendResponse(
        requestId: request.requestId,
        ok: false,
        error: errorMsg,
      );
    }
  } catch (_) {
    // Ignore malformed messages
  }
}

/// Convert the binary payload JS object into a Dart Map.
Map<String, Object?> _jsObjectToMap(JSObject obj) {
  final map = <String, Object?>{};

  // bytesSize (a JS number)
  final sizeField = obj.getProperty<JSNumber?>('bytesSize'.toJS);
  if (sizeField != null) {
    map['bytesSize'] = sizeField.toDartInt;
  }

  // bytes (a JS Uint8Array kept as JSObject for zero-copy transfer)
  final bytesField = obj.getProperty<JSObject?>('bytes'.toJS);
  if (bytesField != null) {
    map['bytes'] = bytesField;
  }

  return map;
}

/// Helper to extract the `data` field from a MessageEvent.
JSAny? _getMessageData(JSObject event) => event.getProperty<JSAny?>('data'.toJS);

// ============================================================================
// Worker Main Entrypoint
// ============================================================================

void main() {
  // Register message handler.
  workerGlobalScope.onmessage =
      ((JSObject event) => _handleMessage(event)).toJS;

  // Initialize toolkit asynchronously.
  unawaited(_initializeToolkit());
}
