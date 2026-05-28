import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:verovio_flutter/src/verovio_bindings.dart';
import 'package:verovio_flutter/src/verovio_loader.dart';
import 'package:verovio_flutter/src/verovio_resource_manager.dart';

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

/// Synchronous wrapper around the native Verovio toolkit.
class VerovioService {
  VerovioService._(this._bindings, this._handle);

  final VerovioNativeBindings _bindings;
  VrvToolkitHandle? _handle;
  bool _disposed = false;

  /// Creates a Verovio toolkit instance backed by the native library.
  static Future<VerovioService> spawn({required String resourcePath}) async {
    if (resourcePath.isEmpty) {
      throw ArgumentError.value(
          resourcePath, 'resourcePath', 'must not be empty');
    }
    if (!Uri.file(resourcePath).isAbsolute) {
      throw ArgumentError.value(
        resourcePath,
        'resourcePath',
        'must be an absolute path',
      );
    }

    await VerovioResourceManager.ensureVerovioAssetsReady();

    final nativeResourcePath = resourcePath.toNativeUtf8();
    try {
      final bindings = VerovioNativeBindings(loadVerovioLibrary());
      final handle = bindings.vrv_ffi_create(nativeResourcePath.cast<Char>());
      if (handle == nullptr) {
        throw StateError('Failed to create Verovio toolkit');
      }
      return VerovioService._(bindings, handle);
    } finally {
      malloc.free(nativeResourcePath);
    }
  }

  VrvToolkitHandle _requireHandle() {
    final handle = _handle;
    if (_disposed || handle == null) {
      throw StateError('VerovioService has been disposed');
    }
    return handle;
  }

  String _readString(Pointer<Char> ptr) {
    try {
      return ptr.cast<Utf8>().toDartString();
    } finally {
      _bindings.vrv_ffi_string_free(ptr);
    }
  }

  String _getLogOrEmpty() {
    final handle = _handle;
    if (_disposed || handle == null) {
      return '';
    }
    final ptr = _bindings.vrv_ffi_get_log(handle);
    if (ptr == nullptr) {
      return '';
    }
    return _readString(ptr);
  }

  String _takeString(Pointer<Char> ptr, String method) {
    if (ptr == nullptr) {
      throw VerovioException(method: method, log: _getLogOrEmpty());
    }
    return _readString(ptr);
  }

  T _withUtf8<T>(String value, T Function(Pointer<Char> nativeValue) fn) {
    final nativeValue = value.toNativeUtf8();
    try {
      return fn(nativeValue.cast<Char>());
    } finally {
      malloc.free(nativeValue);
    }
  }

  T _withBytes<T>(Uint8List bytes, T Function(Pointer<Uint8> nativeBytes) fn) {
    final nativeBytes = malloc.allocate<Uint8>(bytes.length);
    try {
      nativeBytes.asTypedList(bytes.length).setAll(0, bytes);
      return fn(nativeBytes);
    } finally {
      malloc.free(nativeBytes);
    }
  }

  bool _ensureBool(bool value, String method) {
    if (!value) {
      throw VerovioException(method: method, log: _getLogOrEmpty());
    }
    return true;
  }

  int _ensureInt(int value, String method) {
    if (value == -1) {
      throw VerovioException(method: method, log: _getLogOrEmpty());
    }
    return value;
  }

  /// Updates the resource path used by the toolkit.
  /// Updates the resource path used by the toolkit.
  bool setResourcePath(String resourcePath) {
    return _ensureBool(
      _withUtf8(resourcePath, (nativeValue) {
        return _bindings.vrv_ffi_set_resource_path(
          _requireHandle(),
          nativeValue,
        );
      }),
      'setResourcePath',
    );
  }

  /// Applies a JSON string of Verovio options.
  /// Applies a JSON string of Verovio options.
  void setOptionsJson(String json) {
    _ensureBool(
      _withUtf8(json, (nativeValue) {
        return _bindings.vrv_ffi_set_options_json(
          _requireHandle(),
          nativeValue,
        );
      }),
      'setOptionsJson',
    );
  }

  /// Loads input data into the toolkit.
  /// Loads input data into the toolkit.
  void loadData(String data) {
    _ensureBool(
      _withUtf8(data, (nativeValue) {
        return _bindings.vrv_ffi_load_data(
          _requireHandle(),
          nativeValue,
        );
      }),
      'loadData',
    );
  }

  /// Loads zipped input data from a Base64 string.
  /// Loads zipped input data from a Base64 string.
  void loadZipDataBase64(String base64Data) {
    _ensureBool(
      _withUtf8(base64Data, (nativeValue) {
        return _bindings.vrv_ffi_load_zip_data_base64(
          _requireHandle(),
          nativeValue,
        );
      }),
      'loadZipDataBase64',
    );
  }

  /// Loads zipped input data from raw bytes.
  /// Loads zipped input data from raw bytes.
  bool loadZipDataBuffer(Uint8List bytes) {
    return _ensureBool(
      _withBytes(bytes, (nativeBytes) {
        return _bindings.vrv_ffi_load_zip_data_buffer(
          _requireHandle(),
          nativeBytes,
          bytes.length,
        );
      }),
      'loadZipDataBuffer',
    );
  }

  /// Returns the number of pages currently available.
  int get pageCount => _ensureInt(
      _bindings.vrv_ffi_get_page_count(_requireHandle()), 'getPageCount');

  /// Renders the requested page as SVG markup.
  String renderToSvg(int pageNo, {bool xmlDeclaration = false}) {
    return _takeString(
      _bindings.vrv_ffi_render_to_svg(
        _requireHandle(),
        pageNo,
        xmlDeclaration,
      ),
      'renderToSvg',
    );
  }

  /// Returns the current Verovio log output.
  String getLog() {
    return _takeString(_bindings.vrv_ffi_get_log(_requireHandle()), 'getLog');
  }

  /// Returns the native Verovio version string.
  String getVersion() {
    return _takeString(
      _bindings.vrv_ffi_get_version(_requireHandle()),
      'getVersion',
    );
  }

  /// Returns the list of available options as JSON.
  String getAvailableOptions() {
    return _takeString(
      _bindings.vrv_ffi_get_available_options(_requireHandle()),
      'getAvailableOptions',
    );
  }

  /// Returns the default options as JSON.
  String getDefaultOptions() {
    return _takeString(
      _bindings.vrv_ffi_get_default_options(_requireHandle()),
      'getDefaultOptions',
    );
  }

  /// Returns the current option state as JSON.
  String getOptions() {
    return _takeString(
      _bindings.vrv_ffi_get_options(_requireHandle()),
      'getOptions',
    );
  }

  /// Returns a human-readable description of the available options.
  String getOptionUsageString() {
    return _takeString(
      _bindings.vrv_ffi_get_option_usage_string(_requireHandle()),
      'getOptionUsageString',
    );
  }

  /// Returns a description of the features enabled by [jsonOptions].
  String getDescriptiveFeatures(String jsonOptions) {
    return _takeString(
      _withUtf8(jsonOptions, (nativeValue) {
        return _bindings.vrv_ffi_get_descriptive_features(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getDescriptiveFeatures',
    );
  }

  /// Returns the attributes for the element identified by [xmlId].
  String getElementAttr(String xmlId) {
    return _takeString(
      _withUtf8(xmlId, (nativeValue) {
        return _bindings.vrv_ffi_get_element_attr(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getElementAttr',
    );
  }

  /// Returns the elements active at the given time in milliseconds.
  String getElementsAtTime(int millisec) {
    return _takeString(
      _bindings.vrv_ffi_get_elements_at_time(_requireHandle(), millisec),
      'getElementsAtTime',
    );
  }

  /// Returns the expansion IDs for the element identified by [xmlId].
  String getExpansionIdsForElement(String xmlId) {
    return _takeString(
      _withUtf8(xmlId, (nativeValue) {
        return _bindings.vrv_ffi_get_expansion_ids_for_element(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getExpansionIdsForElement',
    );
  }

  /// Returns MIDI values for the element identified by [xmlId].
  String getMidiValuesForElement(String xmlId) {
    return _takeString(
      _withUtf8(xmlId, (nativeValue) {
        return _bindings.vrv_ffi_get_midi_values_for_element(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getMidiValuesForElement',
    );
  }

  /// Returns the notated ID for the element identified by [xmlId].
  String getNotatedIdForElement(String xmlId) {
    return _takeString(
      _withUtf8(xmlId, (nativeValue) {
        return _bindings.vrv_ffi_get_notated_id_for_element(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getNotatedIdForElement',
    );
  }

  /// Returns the times associated with the element identified by [xmlId].
  String getTimesForElement(String xmlId) {
    return _takeString(
      _withUtf8(xmlId, (nativeValue) {
        return _bindings.vrv_ffi_get_times_for_element(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getTimesForElement',
    );
  }

  /// Returns the toolkit instance ID.
  String getId() {
    return _takeString(_bindings.vrv_ffi_get_id(_requireHandle()), 'getId');
  }

  /// Returns the currently configured resource path.
  String getResourcePath() {
    return _takeString(
      _bindings.vrv_ffi_get_resource_path(_requireHandle()),
      'getResourcePath',
    );
  }

  /// Returns the current score as Humdrum text.
  String getHumdrum() {
    return _takeString(
      _bindings.vrv_ffi_get_humdrum(_requireHandle()),
      'getHumdrum',
    );
  }

  /// Returns the current score as MEI using [jsonOptions].
  String getMei(String jsonOptions) {
    return _takeString(
      _withUtf8(jsonOptions, (nativeValue) {
        return _bindings.vrv_ffi_get_mei(_requireHandle(), nativeValue);
      }),
      'getMei',
    );
  }

  /// Converts Humdrum input to normalized Humdrum output.
  String convertHumdrumToHumdrum(String data) {
    return _takeString(
      _withUtf8(data, (nativeValue) {
        return _bindings.vrv_ffi_convert_humdrum_to_humdrum(
          _requireHandle(),
          nativeValue,
        );
      }),
      'convertHumdrumToHumdrum',
    );
  }

  /// Converts Humdrum input to Base64-encoded MIDI data.
  String convertHumdrumToMidi(String data) {
    return _takeString(
      _withUtf8(data, (nativeValue) {
        return _bindings.vrv_ffi_convert_humdrum_to_midi(
          _requireHandle(),
          nativeValue,
        );
      }),
      'convertHumdrumToMidi',
    );
  }

  /// Converts Humdrum input directly to MIDI bytes.
  Uint8List convertHumdrumToMidiBytes(String data) {
    return base64Decode(convertHumdrumToMidi(data));
  }

  /// Converts MEI input to Humdrum text.
  String convertMeiToHumdrum(String data) {
    return _takeString(
      _withUtf8(data, (nativeValue) {
        return _bindings.vrv_ffi_convert_mei_to_humdrum(
          _requireHandle(),
          nativeValue,
        );
      }),
      'convertMeiToHumdrum',
    );
  }

  /// Returns the current editor information string.
  String editInfo() {
    return _takeString(
        _bindings.vrv_ffi_edit_info(_requireHandle()), 'editInfo');
  }

  /// Validates PAE input and returns the result string.
  String validatePae(String data) {
    return _takeString(
      _withUtf8(data, (nativeValue) {
        return _bindings.vrv_ffi_validate_pae(_requireHandle(), nativeValue);
      }),
      'validatePae',
    );
  }

  /// Renders arbitrary input data using the provided JSON options.
  String renderData(String data, String jsonOptions) {
    return _takeString(
      _withUtf8(data, (nativeData) {
        return _withUtf8(jsonOptions, (nativeOptions) {
          return _bindings.vrv_ffi_render_data(
            _requireHandle(),
            nativeData,
            nativeOptions,
          );
        });
      }),
      'renderData',
    );
  }

  /// Renders the current score to Base64-encoded MIDI data.
  /// Renders the current score to Base64-encoded MIDI data.
  String renderToMidi() {
    return _takeString(
      _bindings.vrv_ffi_render_to_midi(_requireHandle()),
      'renderToMidi',
    );
  }

  /// Renders the current score to MIDI bytes.
  /// Renders the current score to MIDI bytes.
  Uint8List renderToMidiBytes() => base64Decode(renderToMidi());

  /// Renders the current score to PAE text.
  String renderToPae() {
    return _takeString(
      _bindings.vrv_ffi_render_to_pae(_requireHandle()),
      'renderToPae',
    );
  }

  /// Renders the current score to a time map.
  String renderToTimemap({String jsonOptions = ''}) {
    return _takeString(
      _withUtf8(jsonOptions, (nativeValue) {
        return _bindings.vrv_ffi_render_to_timemap(
            _requireHandle(), nativeValue);
      }),
      'renderToTimemap',
    );
  }

  /// Renders the current score to an expansion map.
  String renderToExpansionMap() {
    return _takeString(
      _bindings.vrv_ffi_render_to_expansion_map(_requireHandle()),
      'renderToExpansionMap',
    );
  }

  /// Returns the current engraving scale.
  /// Returns the current engraving scale.
  int getScale() {
    return _ensureInt(
      _bindings.vrv_ffi_get_scale(_requireHandle()),
      'getScale',
    );
  }

  /// Sets the engraving scale.
  /// Sets the engraving scale.
  bool setScale(int scale) {
    return _ensureBool(
      _bindings.vrv_ffi_set_scale(_requireHandle(), scale),
      'setScale',
    );
  }

  /// Returns the page that contains the element identified by [xmlId].
  int getPageWithElement(String xmlId) {
    return _ensureInt(
      _withUtf8(xmlId, (nativeValue) {
        return _bindings.vrv_ffi_get_page_with_element(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getPageWithElement',
    );
  }

  /// Returns the time position for the element identified by [xmlId].
  int getTimeForElement(String xmlId) {
    return _ensureInt(
      _withUtf8(xmlId, (nativeValue) {
        return _bindings.vrv_ffi_get_time_for_element(
          _requireHandle(),
          nativeValue,
        );
      }),
      'getTimeForElement',
    );
  }

  /// Applies a selection described by [selectionJson].
  bool select(String selectionJson) {
    return _ensureBool(
      _withUtf8(selectionJson, (nativeValue) {
        return _bindings.vrv_ffi_select(_requireHandle(), nativeValue);
      }),
      'select',
    );
  }

  /// Sets the current input format.
  bool setInputFrom(String inputFrom) {
    return _ensureBool(
      _withUtf8(inputFrom, (nativeValue) {
        return _bindings.vrv_ffi_set_input_from(_requireHandle(), nativeValue);
      }),
      'setInputFrom',
    );
  }

  /// Sets the current output format.
  bool setOutputTo(String outputTo) {
    return _ensureBool(
      _withUtf8(outputTo, (nativeValue) {
        return _bindings.vrv_ffi_set_output_to(_requireHandle(), nativeValue);
      }),
      'setOutputTo',
    );
  }

  /// Applies an editor action string.
  bool edit(String editorAction) {
    return _withUtf8(
      editorAction,
      (nativeValue) {
        return _bindings.vrv_ffi_edit(_requireHandle(), nativeValue);
      },
    );
  }

  /// Recomputes the layout using optional JSON options.
  void redoLayout({String jsonOptions = ''}) {
    _withUtf8(jsonOptions, (nativeValue) {
      _bindings.vrv_ffi_redo_layout(_requireHandle(), nativeValue);
      return true;
    });
  }

  /// Recomputes the page pitch-position layout.
  void redoPagePitchPosLayout() {
    _bindings.vrv_ffi_redo_page_pitch_pos_layout(_requireHandle());
  }

  /// Resets all options to their defaults.
  void resetOptions() {
    _bindings.vrv_ffi_reset_options(_requireHandle());
  }

  /// Resets the XML ID seed to [seed].
  void resetXmlIdSeed(int seed) {
    _bindings.vrv_ffi_reset_xml_id_seed(_requireHandle(), seed);
  }

  /// Releases the native toolkit handle.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    final handle = _handle;
    _disposed = true;
    _handle = null;
    if (handle != null) {
      _bindings.vrv_ffi_destroy(handle);
    }
  }
}
