import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:verovio_flutter/src/verovio_bindings.dart';
import 'package:verovio_flutter/src/verovio_loader.dart';
import 'package:verovio_flutter/src/verovio_resource_manager.dart';

class VerovioException implements Exception {
  VerovioException({required this.method, this.log = ''});

  final String method;
  final String log;

  @override
  String toString() => 'VerovioException(method: $method, log: $log)';
}

class VerovioService {
  VerovioService._(this._bindings, this._handle);

  final VerovioNativeBindings _bindings;
  VrvToolkitHandle? _handle;
  bool _disposed = false;

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

  int get pageCount => _ensureInt(
      _bindings.vrv_ffi_get_page_count(_requireHandle()), 'getPageCount');

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

  String getLog() {
    return _takeString(_bindings.vrv_ffi_get_log(_requireHandle()), 'getLog');
  }

  String getVersion() {
    return _takeString(
      _bindings.vrv_ffi_get_version(_requireHandle()),
      'getVersion',
    );
  }

  String getAvailableOptions() {
    return _takeString(
      _bindings.vrv_ffi_get_available_options(_requireHandle()),
      'getAvailableOptions',
    );
  }

  String getDefaultOptions() {
    return _takeString(
      _bindings.vrv_ffi_get_default_options(_requireHandle()),
      'getDefaultOptions',
    );
  }

  String getOptions() {
    return _takeString(
      _bindings.vrv_ffi_get_options(_requireHandle()),
      'getOptions',
    );
  }

  String getOptionUsageString() {
    return _takeString(
      _bindings.vrv_ffi_get_option_usage_string(_requireHandle()),
      'getOptionUsageString',
    );
  }

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

  String getElementsAtTime(int millisec) {
    return _takeString(
      _bindings.vrv_ffi_get_elements_at_time(_requireHandle(), millisec),
      'getElementsAtTime',
    );
  }

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

  String getId() {
    return _takeString(_bindings.vrv_ffi_get_id(_requireHandle()), 'getId');
  }

  String getResourcePath() {
    return _takeString(
      _bindings.vrv_ffi_get_resource_path(_requireHandle()),
      'getResourcePath',
    );
  }

  String getHumdrum() {
    return _takeString(
      _bindings.vrv_ffi_get_humdrum(_requireHandle()),
      'getHumdrum',
    );
  }

  String getMei(String jsonOptions) {
    return _takeString(
      _withUtf8(jsonOptions, (nativeValue) {
        return _bindings.vrv_ffi_get_mei(_requireHandle(), nativeValue);
      }),
      'getMei',
    );
  }

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

  Uint8List convertHumdrumToMidiBytes(String data) {
    return base64Decode(convertHumdrumToMidi(data));
  }

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

  String editInfo() {
    return _takeString(
        _bindings.vrv_ffi_edit_info(_requireHandle()), 'editInfo');
  }

  String validatePae(String data) {
    return _takeString(
      _withUtf8(data, (nativeValue) {
        return _bindings.vrv_ffi_validate_pae(_requireHandle(), nativeValue);
      }),
      'validatePae',
    );
  }

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

  String renderToMidi() {
    return _takeString(
      _bindings.vrv_ffi_render_to_midi(_requireHandle()),
      'renderToMidi',
    );
  }

  Uint8List renderToMidiBytes() => base64Decode(renderToMidi());

  String renderToPae() {
    return _takeString(
      _bindings.vrv_ffi_render_to_pae(_requireHandle()),
      'renderToPae',
    );
  }

  String renderToTimemap({String jsonOptions = ''}) {
    return _takeString(
      _withUtf8(jsonOptions, (nativeValue) {
        return _bindings.vrv_ffi_render_to_timemap(
            _requireHandle(), nativeValue);
      }),
      'renderToTimemap',
    );
  }

  String renderToExpansionMap() {
    return _takeString(
      _bindings.vrv_ffi_render_to_expansion_map(_requireHandle()),
      'renderToExpansionMap',
    );
  }

  int getScale() {
    return _ensureInt(
      _bindings.vrv_ffi_get_scale(_requireHandle()),
      'getScale',
    );
  }

  bool setScale(int scale) {
    return _ensureBool(
      _bindings.vrv_ffi_set_scale(_requireHandle(), scale),
      'setScale',
    );
  }

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

  bool select(String selectionJson) {
    return _ensureBool(
      _withUtf8(selectionJson, (nativeValue) {
        return _bindings.vrv_ffi_select(_requireHandle(), nativeValue);
      }),
      'select',
    );
  }

  bool setInputFrom(String inputFrom) {
    return _ensureBool(
      _withUtf8(inputFrom, (nativeValue) {
        return _bindings.vrv_ffi_set_input_from(_requireHandle(), nativeValue);
      }),
      'setInputFrom',
    );
  }

  bool setOutputTo(String outputTo) {
    return _ensureBool(
      _withUtf8(outputTo, (nativeValue) {
        return _bindings.vrv_ffi_set_output_to(_requireHandle(), nativeValue);
      }),
      'setOutputTo',
    );
  }

  bool edit(String editorAction) {
    return _withUtf8(
      editorAction,
      (nativeValue) {
        return _bindings.vrv_ffi_edit(_requireHandle(), nativeValue);
      },
    );
  }

  void redoLayout({String jsonOptions = ''}) {
    _withUtf8(jsonOptions, (nativeValue) {
      _bindings.vrv_ffi_redo_layout(_requireHandle(), nativeValue);
      return true;
    });
  }

  void redoPagePitchPosLayout() {
    _bindings.vrv_ffi_redo_page_pitch_pos_layout(_requireHandle());
  }

  void resetOptions() {
    _bindings.vrv_ffi_reset_options(_requireHandle());
  }

  void resetXmlIdSeed(int seed) {
    _bindings.vrv_ffi_reset_xml_id_seed(_requireHandle(), seed);
  }

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
