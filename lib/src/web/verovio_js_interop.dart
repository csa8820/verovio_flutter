/// JavaScript interop bindings for Verovio 6.2.0 WASM toolkit.
///
/// This file provides dart:js_interop access to the official Verovio WASM/JS
/// toolkit exposed by verovio-toolkit-wasm.js (6.2.0, equivalent to native 6.2.1).
library verovio_js_interop;
///
/// ## Method Reference
///
/// All method names, signatures, and return types correspond exactly to the
/// emscripten-proxy.js cwrap() mappings and the VerovioToolkit wrapper class.
///
/// See:
/// - third_party/verovio/emscripten/npm/src/emscripten-proxy.js (cwrap mappings)
/// - third_party/verovio/emscripten/npm/src/verovio-toolkit.js (wrapper class)
/// - Verified against actual 6.2.0 production build in web/verovio/
///
/// ## Usage in C2+ (Web Worker)
///
/// In web/verovio_worker.dart (C2 phase entrypoint):
/// 1. Import this file (along with verovio-toolkit-wasm.js via <script>)
/// 2. Call `await waitForRuntimeReady()` to wait for WASM initialization
/// 3. Create a toolkit: `final toolkit = VerovioToolkit(verovioModule!);`
/// 4. Call methods: `toolkit.loadData(mxmlString)`, `toolkit.renderToSVG(1, 0)`, etc.
/// 5. Clean up: `toolkit.destroy()`
///
/// ## Compilation
///
/// ⚠️ **WEB-ONLY**: This file uses dart:js_interop and MUST NOT be imported
/// by IO/mobile compilation paths. It will cause compilation failure with:
/// "The identifier 'dart:js_interop' is not available outside the web platform."
///
/// Isolation is handled by conditional imports in lib/src/worker/*.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// ============================================================================
// Module and Runtime Initialization
// ============================================================================

/// Type for the Verovio WASM module object.
/// Contains onRuntimeInitialized callback and memory utilities.
extension type VerovioModule(JSObject _) implements JSObject {
  /// Called by the emscripten runtime after WASM initialization is complete.
  /// Set a callback function to be invoked once the module is ready.
  external set onRuntimeInitialized(JSFunction? callback);

  /// Emscripten sets this to true once `run()` has finished.
  ///
  /// Before initialization completes the property may be `undefined`, so this
  /// is nullable; treat null as "not yet run".
  external bool? get calledRun;

  /// Low-level malloc for allocating WASM heap memory.
  /// Used internally by toolkit for buffer operations (D1.1 phase).
  // ignore: unused_element
  external int _malloc(int size);

  /// Low-level free for releasing WASM heap memory.
  /// Used internally by toolkit for buffer cleanup (D1.1 phase).
  // ignore: unused_element
  external void _free(int ptr);

  /// Raw heap memory as Uint8Array (HEAPU8).
  /// Allows direct read/write of WASM memory for buffer operations (D1.1 phase).
  // ignore: non_constant_identifier_names
  external JSUint8Array get HEAPU8;
}

/// Represents a Uint8Array in JavaScript for memory operations.
extension type JSUint8Array(JSObject _) implements JSObject {
  /// Copy data from Dart Uint8List to WASM heap memory.
  /// Used by toolkit for binary data (ZIP files, MIDI, etc.).
  external void set(JSArray<JSNumber> array, int offset);
}

/// Access the global `verovio` wrapper exposed by verovio-toolkit-wasm.js.
///
/// The UMD export is NOT the emscripten Module itself; it is a wrapper object
/// shaped like `{ module, toolkit, LOG_OFF, ..., enableLog, ... }` where:
///  - `module`  is the emscripten Module (carries onRuntimeInitialized/calledRun)
///  - `toolkit` is the VerovioToolkit constructor function
/// Returns null until the toolkit script has been loaded.
@JS('verovio')
external JSObject? get _verovioGlobal;

/// The emscripten Module backing the Verovio toolkit (`verovio.module`).
///
/// This is the object that exposes `onRuntimeInitialized` and `calledRun`, used
/// to detect when the WASM runtime is ready. Returns null until
/// verovio-toolkit-wasm.js has been loaded.
VerovioModule? get verovioModule {
  final global = _verovioGlobal;
  if (global == null) {
    return null;
  }
  final module = global.getProperty<JSObject?>('module'.toJS);
  return module == null ? null : VerovioModule(module);
}

// ============================================================================
// VerovioToolkit Class (instance wrapper)
// ============================================================================

/// Dart-facing interface to a single VerovioToolkit instance.
/// The actual toolkit is instantiated in JavaScript via: new Toolkit(module)
/// All methods delegate to the underlying JS proxy which calls emscripten cwrap functions.
///
/// ### Lifecycle:
/// 1. Await module initialization via waitForRuntimeReady()
/// 2. Create instance: toolkit = VerovioToolkit._create(module)
/// 3. Call methods (loadData, setOptions, render*, etc.)
/// 4. Cleanup: toolkit.destroy() when done
/// Convert a JSON string into a JS value for toolkit methods whose JS wrapper
/// calls `JSON.stringify()` on the argument (e.g. setOptions, select).
///
/// Passing a raw JSON string to those wrappers would double-encode it, so we
/// parse it here and hand over a real JS object/array.
JSAny _jsonStringToJs(String json) {
  final trimmed = json.trim();
  if (trimmed.isEmpty) {
    return JSObject();
  }
  return (jsonDecode(trimmed) as Object?).jsify() ?? JSObject();
}

/// Convert a JS value returned by a toolkit method (whose JS wrapper returns
/// `JSON.parse(...)`) back into a JSON string for the worker protocol.
String _jsToJsonString(JSAny? value) {
  if (value == null) {
    return '';
  }
  return jsonEncode(value.dartify());
}

extension type VerovioToolkit(JSObject _) implements JSObject {
  /// Factory constructor: instantiate toolkit from the WASM module.
  /// Must be called AFTER the module is runtime-initialized.
  static VerovioToolkit create(VerovioModule module) => _createToolkit(module);

  /// Destructor: clean up internal C++ toolkit resources.
  /// Called automatically when toolkit instance is garbage collected,
  /// but explicit destroy() ensures immediate cleanup.
  external void destroy();

  // ========================================================================
  // Core Methods (C1 phase: required for basic rendering)
  // ========================================================================

  /// Load MusicXML/MEI data as a string.
  /// Returns true if parsing succeeded, false if data is malformed.
  /// Signature: bool loadData(Toolkit *ic, const char *data)
  ///
  /// The emscripten cwrap returns a JS number (1/0), so we accept JSAny and
  /// coerce to bool via truthiness.
  @JS('loadData')
  external JSAny _loadData(String data);
  bool loadData(String data) => _loadData(data).isTruthy.toDart;

  /// Set rendering options from a JSON string.
  /// Options control page layout, staff spacing, fonts, etc.
  /// Common options: "pageHeight", "pageWidth", "pageMarginTop", etc.
  /// See getAvailableOptions() for the full list.
  /// Signature: void setOptions(Toolkit *ic, const char *options)
  ///
  /// The JS wrapper calls JSON.stringify() on the argument, so we pass a parsed
  /// JS object rather than the raw JSON string.
  @JS('setOptions')
  external void _setOptions(JSAny options);
  void setOptions(String options) => _setOptions(_jsonStringToJs(options));

  /// Get the total number of pages in the currently loaded score.
  /// Returns 0 if no data is loaded.
  /// Signature: int getPageCount(Toolkit *ic)
  external int getPageCount();

  /// Render a specific page to SVG string.
  /// @param pageNo 1-indexed page number (1..getPageCount())
  /// @param xmlDeclaration 0/1 (JS bool as int): include XML declaration in SVG?
  /// Returns: SVG as a string, ready for display in HTML.
  /// Signature: char *renderToSVG(Toolkit *ic, int pageNo, int xmlDeclaration)
  external String renderToSVG(int pageNo, int xmlDeclaration);

  /// Get the Verovio version string (e.g., "6.2.0-43f8060").
  /// Signature: char *getVersion(Toolkit *ic)
  external String getVersion();

  /// Get the last error/warning log from the toolkit.
  /// Returns a concatenated string of all logged messages since last clear.
  /// Signature: char *getLog(Toolkit *ic)
  external String getLog();

  // ========================================================================
  // Additional Methods (D phase onwards: extend as needed)
  // Pre-bound for convenience, but C1 phase does not require these.
  // All methods below correspond to cwrap entries in emscripten-proxy.js.
  // ========================================================================

  /// Load ZIP/MXL archive from base64-encoded string.
  /// The base64 is decoded and processed as a ZIP file containing MXL structure.
  /// Signature: bool loadZipDataBase64(Toolkit *ic, const char *data)
  @JS('loadZipDataBase64')
  external JSAny _loadZipDataBase64(String data);
  bool loadZipDataBase64(String data) =>
      _loadZipDataBase64(data).isTruthy.toDart;

  /// Load ZIP/MXL archive from raw bytes.
  ///
  /// The JS toolkit wrapper takes a single argument that MUST be an
  /// `ArrayBuffer` (it computes the size itself); passing a typed-array view
  /// is rejected. Returns true if parsing succeeded.
  @JS('loadZipDataBuffer')
  external JSAny _loadZipDataBuffer(JSObject arrayBuffer);
  bool loadZipDataBuffer(JSObject arrayBuffer) =>
      _loadZipDataBuffer(arrayBuffer).isTruthy.toDart;

  /// Redo layout with new options (e.g., after setOptions, without reload).
  /// Signature: void redoLayout(Toolkit *ic, const char *options)
  /// The JS wrapper JSON.stringify()s the argument, so pass a parsed object.
  @JS('redoLayout')
  external void _redoLayout(JSAny options);
  void redoLayout(String options) => _redoLayout(_jsonStringToJs(options));

  /// Redo pitch-position layout (for tablature and other special formatting).
  /// Signature: void redoPagePitchPosLayout(Toolkit *ic)
  external void redoPagePitchPosLayout();

  /// Reset all options to defaults.
  /// Signature: void resetOptions(Toolkit *ic)
  external void resetOptions();

  /// Reset the XML ID seed counter (for reproducible IDs).
  /// Signature: void resetXmlIdSeed(Toolkit *ic, int seed)
  external void resetXmlIdSeed(int seed);

  /// Render to MIDI data (base64-encoded).
  /// Returns: base64 string of MIDI bytes, ready for decode/playback.
  /// Signature: char *renderToMIDI(Toolkit *ic)
  external String renderToMIDI();

  /// Render to Plaine and Easie notation.
  /// Signature: char *renderToPAE(Toolkit *ic)
  external String renderToPAE();

  /// Render to timing map (timemap): JSON correlating time to visual position.
  /// Useful for synchronized playback / hit detection.
  /// Signature: char *renderToTimemap(Toolkit *ic, const char *options)
  /// The JS wrapper takes an options object and returns a parsed JS object.
  @JS('renderToTimemap')
  external JSAny? _renderToTimemap(JSAny options);
  String renderToTimemap(String options) =>
      _jsToJsonString(_renderToTimemap(_jsonStringToJs(options)));

  /// Render to expansion map (for repeats, expansions, etc.).
  /// Returns JSON representation.
  /// Signature: char *renderToExpansionMap(Toolkit *ic)
  @JS('renderToExpansionMap')
  external JSAny? _renderToExpansionMap();
  String renderToExpansionMap() => _jsToJsonString(_renderToExpansionMap());

  /// Render data (score and options) to SVG in one call.
  /// Signature: char *renderData(Toolkit *ic, const char *data, const char *options)
  external String renderData(String data, String options);

  /// Get MEI (Music Encoding Initiative) representation of the score.
  /// @param options JSON string with export options (e.g., {"scoreBased": true})
  /// Returns: MEI XML as a string.
  /// Signature: char *getMEI(Toolkit *ic, const char *options)
  /// The JS wrapper JSON.stringify()s the options object; output is a string.
  @JS('getMEI')
  external String _getMEI(JSAny options);
  String getMEI(String options) => _getMEI(_jsonStringToJs(options));

  /// Get available rendering/parsing options as JSON.
  /// Useful for UI generation and validation.
  /// Signature: char *getAvailableOptions(Toolkit *ic)
  /// The JS wrapper returns a parsed JS object; we re-encode it to JSON.
  @JS('getAvailableOptions')
  external JSAny? _getAvailableOptions();
  String getAvailableOptions() => _jsToJsonString(_getAvailableOptions());

  /// Get default values for all options.
  /// Signature: char *getDefaultOptions(Toolkit *ic)
  @JS('getDefaultOptions')
  external JSAny? _getDefaultOptions();
  String getDefaultOptions() => _jsToJsonString(_getDefaultOptions());

  /// Get current option values.
  /// Signature: char *getOptions(Toolkit *ic)
  @JS('getOptions')
  external JSAny? _getOptions();
  String getOptions() => _jsToJsonString(_getOptions());

  /// Get element attributes by XML ID.
  /// Returns JSON with position, duration, staff, etc.
  /// Signature: char *getElementAttr(Toolkit *ic, const char *xmlId)
  /// The JS wrapper returns a parsed JS object; we re-encode it to JSON.
  @JS('getElementAttr')
  external JSAny? _getElementAttr(String xmlId);
  String getElementAttr(String xmlId) =>
      _jsToJsonString(_getElementAttr(xmlId));

  /// Get elements active at a specific time (in milliseconds).
  /// Returns JSON array of element IDs.
  /// Signature: char *getElementsAtTime(Toolkit *ic, int time)
  @JS('getElementsAtTime')
  external JSAny? _getElementsAtTime(int millisec);
  String getElementsAtTime(int millisec) =>
      _jsToJsonString(_getElementsAtTime(millisec));

  /// Get the page number containing a given element.
  /// Signature: int getPageWithElement(Toolkit *ic, const char *xmlId)
  external int getPageWithElement(String xmlId);

  /// Get the time (in milliseconds) of an element.
  /// Returns double-precision floating-point time value.
  /// Signature: double getTimeForElement(Toolkit *ic, const char *xmlId)
  external double getTimeForElement(String xmlId);

  /// Get all time values for an element (as JSON).
  /// Signature: char *getTimesForElement(Toolkit *ic, const char *xmlId)
  /// The JS wrapper returns a parsed JS object; we re-encode it to JSON.
  @JS('getTimesForElement')
  external JSAny? _getTimesForElement(String xmlId);
  String getTimesForElement(String xmlId) =>
      _jsToJsonString(_getTimesForElement(xmlId));

  /// Get MIDI values (pitch, velocity, etc.) for an element.
  /// Returns JSON representation of MIDI note data.
  /// Signature: char *getMIDIValuesForElement(Toolkit *ic, const char *xmlId)
  @JS('getMIDIValuesForElement')
  external JSAny? _getMIDIValuesForElement(String xmlId);
  String getMIDIValuesForElement(String xmlId) =>
      _jsToJsonString(_getMIDIValuesForElement(xmlId));

  /// Select elements matching a criteria (JSON).
  /// Affects subsequent rendering (e.g., highlight/edit visualization).
  /// Returns true if selection succeeded.
  /// Signature: bool select(Toolkit *ic, const char *options)
  /// The JS wrapper JSON.stringify()s the selection object and returns 0/1.
  @JS('select')
  external JSAny _select(JSAny selection);
  bool select(String selection) =>
      _select(_jsonStringToJs(selection)).isTruthy.toDart;

  /// Edit the score based on an editor action (JSON).
  /// Modifies the internal score tree.
  /// Returns true if edit succeeded.
  /// Signature: bool edit(Toolkit *ic, const char *editorAction)
  /// The JS wrapper JSON.stringify()s the action object and returns 0/1.
  @JS('edit')
  external JSAny _edit(JSAny editorAction);
  bool edit(String editorAction) =>
      _edit(_jsonStringToJs(editorAction)).isTruthy.toDart;

  /// Get information about the last edit operation.
  /// Returns JSON with edit result and side effects.
  /// Signature: char *editInfo(Toolkit *ic)
  /// The JS wrapper returns a parsed JS object; we re-encode it to JSON.
  @JS('editInfo')
  external JSAny? _editInfo();
  String editInfo() => _jsToJsonString(_editInfo());

  /// Validate Plaine and Easie (PAE) notation string.
  /// Returns JSON with validation results.
  /// Signature: char *validatePAE(Toolkit *ic, const char *options)
  /// Input is a PAE string; the JS wrapper returns a parsed JS object.
  @JS('validatePAE')
  external JSAny? _validatePAE(String data);
  String validatePAE(String data) => _jsToJsonString(_validatePAE(data));

  /// Get notated (original) ID for a given element ID.
  /// Useful for tracking through expansions.
  /// Signature: char *getNotatedIdForElement(Toolkit *ic, const char *xmlId)
  external String getNotatedIdForElement(String xmlId);

  /// Get expansion IDs for an element (when repeats/expansions are applied).
  /// Returns JSON array of expansion IDs.
  /// Signature: char *getExpansionIdsForElement(Toolkit *ic, const char *xmlId)
  /// The JS wrapper returns a parsed JS object; we re-encode it to JSON.
  @JS('getExpansionIdsForElement')
  external JSAny? _getExpansionIdsForElement(String xmlId);
  String getExpansionIdsForElement(String xmlId) =>
      _jsToJsonString(_getExpansionIdsForElement(xmlId));

  /// Get Humdrum representation of the score.
  /// Signature: char *getHumdrum(Toolkit *ic)
  external String getHumdrum();

  /// Convert MEI to Humdrum notation.
  /// Signature: char *convertMEIToHumdrum(Toolkit *ic, const char *meiData)
  external String convertMEIToHumdrum(String meiData);

  /// Convert Humdrum to Humdrum (normalization/variant).
  /// Signature: char *convertHumdrumToHumdrum(Toolkit *ic, const char *humdrumData)
  external String convertHumdrumToHumdrum(String humdrumData);

  /// Convert Humdrum to MIDI (base64-encoded).
  /// Signature: char *convertHumdrumToMIDI(Toolkit *ic, const char *humdrumData)
  external String convertHumdrumToMIDI(String humdrumData);

  /// Get descriptive features of the score.
  /// Signature: char *getDescriptiveFeatures(Toolkit *ic, const char *options)
  /// The JS wrapper takes an options object and returns a parsed JS object.
  @JS('getDescriptiveFeatures')
  external JSAny? _getDescriptiveFeatures(JSAny options);
  String getDescriptiveFeatures(String options) =>
      _jsToJsonString(_getDescriptiveFeatures(_jsonStringToJs(options)));
}

// ============================================================================
// Module Initialization Utilities
// ============================================================================

/// Wait for the Verovio WASM module to finish runtime initialization.
/// This must be called before creating a VerovioToolkit instance.
///
/// The initialization includes:
/// - Loading and parsing verovio.wasm
/// - Setting up emscripten runtime (memory, malloc/free, etc.)
/// - Initializing the toolkit C++ library
///
/// The handshake is deliberately tolerant of timing: in the Web Worker setup
/// the toolkit script is loaded via `importScripts` and emscripten may finish
/// its asynchronous `run()` either before or after Dart starts awaiting here.
/// We therefore:
///   1. Return immediately when `Module.calledRun` is already true.
///   2. Otherwise register `onRuntimeInitialized` to be notified.
///   3. Also poll `calledRun` as a safety net, since emscripten can overwrite
///      the callback or complete in a way that never re-invokes ours.
Future<void> waitForRuntimeReady() async {
  final module = verovioModule;
  if (module == null) {
    throw Exception(
      'Verovio module not found. '
      'Ensure verovio-toolkit-wasm.js has been loaded before awaiting runtime initialization.'
    );
  }

  // Fast path: the runtime is already usable.
  if (module.calledRun ?? false) {
    return;
  }

  final completer = Completer<void>();

  void tryComplete() {
    if (!completer.isCompleted && (module.calledRun ?? false)) {
      completer.complete();
    }
  }

  // Register the emscripten callback (fires once init finishes).
  module.onRuntimeInitialized = (() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }).toJS;

  // Re-check: initialization may have completed between the `calledRun` check
  // above and installing the callback.
  tryComplete();

  // Polling safety net for the "already ready / callback never fires" case.
  final poll = Timer.periodic(const Duration(milliseconds: 25), (timer) {
    tryComplete();
    if (completer.isCompleted) {
      timer.cancel();
    }
  });

  try {
    await completer.future;
  } finally {
    poll.cancel();
  }
}

/// Create a VerovioToolkit instance from the WASM module.
///
/// The toolkit constructor lives on the global `verovio` wrapper
/// (`verovio.toolkit`), not as a standalone global class, so we invoke
/// `new verovio.toolkit(module)` via js_interop.
VerovioToolkit _createToolkit(VerovioModule module) {
  final global = _verovioGlobal;
  if (global == null) {
    throw StateError(
      'Verovio global not loaded; cannot create toolkit instance.',
    );
  }
  final ctor = global.getProperty<JSFunction>('toolkit'.toJS);
  final instance = ctor.callAsConstructorVarArgs<JSObject>(<JSAny?>[module]);
  return VerovioToolkit(instance);
}
