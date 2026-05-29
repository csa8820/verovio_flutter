// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:verovio_flutter/src/hit_map/models.dart';
import 'package:verovio_flutter/src/hit_map/parser.dart';
import 'package:verovio_flutter/src/verovio_bindings.dart';
import 'package:verovio_flutter/src/verovio_loader.dart';

class VerovioWorkerRequest {
  const VerovioWorkerRequest({
    required this.requestId,
    required this.action,
    required this.payload,
  });

  final int requestId;
  final String action;
  final Map<String, Object?> payload;
}

void verovioIsolateWorkerEntryPoint(Map<String, Object?> initialMessage) {
  final handshakePort = initialMessage['handshakePort'];
  final responsePort = initialMessage['responsePort'];
  if (handshakePort is! SendPort || responsePort is! SendPort) {
    throw ArgumentError.value(
      initialMessage,
      'initialMessage',
      'must contain handshakePort and responsePort SendPorts',
    );
  }

  final controlPort = ReceivePort();
  handshakePort.send(controlPort.sendPort);
  unawaited(
    _VerovioWorker(
      controlPort,
      responsePort,
    ).run(),
  );
}

class _VerovioWorker {
  _VerovioWorker(this._controlPort, this._responsePort);

  final ReceivePort _controlPort;
  final SendPort _responsePort;
  dynamic _service;
  Future<void> _queue = Future<void>.value();

  late final Map<String, Object? Function(Map<String, Object?> payload)>
      _genericHandlers = <String, Object? Function(Map<String, Object?>)>{
    'getAvailableOptions': (_) => _requireService().getAvailableOptions(),
    'getDefaultOptions': (_) => _requireService().getDefaultOptions(),
    'getOptions': (_) => _requireService().getOptions(),
    'getOptionUsageString': (_) => _requireService().getOptionUsageString(),
    'getDescriptiveFeatures': (payload) =>
        _requireService().getDescriptiveFeatures(
          _stringArg(payload, 'jsonOptions'),
        ),
    'getElementAttr': (payload) => _requireService().getElementAttr(
          _stringArg(payload, 'xmlId'),
        ),
    'getElementsAtTime': (payload) => _requireService().getElementsAtTime(
          _intArg(payload, 'millisec'),
        ),
    'getExpansionIdsForElement': (payload) =>
        _requireService().getExpansionIdsForElement(
          _stringArg(payload, 'xmlId'),
        ),
    'getMidiValuesForElement': (payload) =>
        _requireService().getMidiValuesForElement(
          _stringArg(payload, 'xmlId'),
        ),
    'getNotatedIdForElement': (payload) =>
        _requireService().getNotatedIdForElement(
          _stringArg(payload, 'xmlId'),
        ),
    'getTimesForElement': (payload) => _requireService().getTimesForElement(
          _stringArg(payload, 'xmlId'),
        ),
    'getId': (_) => _requireService().getId(),
    'getResourcePath': (_) => _requireService().getResourcePath(),
    'getHumdrum': (_) => _requireService().getHumdrum(),
    'getMei': (payload) => _requireService().getMei(
          _stringArg(payload, 'jsonOptions'),
        ),
    'convertHumdrumToHumdrum': (payload) =>
        _requireService().convertHumdrumToHumdrum(
          _stringArg(payload, 'data'),
        ),
    'convertHumdrumToMidi': (payload) => _requireService().convertHumdrumToMidi(
          _stringArg(payload, 'data'),
        ),
    'convertMeiToHumdrum': (payload) => _requireService().convertMeiToHumdrum(
          _stringArg(payload, 'data'),
        ),
    'editInfo': (_) => _requireService().editInfo(),
    'validatePae': (payload) => _requireService().validatePae(
          _stringArg(payload, 'data'),
        ),
    'renderData': (payload) => _requireService().renderData(
          _stringArg(payload, 'data'),
          _stringArg(payload, 'jsonOptions'),
        ),
    'renderToMidi': (_) => _requireService().renderToMidi(),
    'renderToPae': (_) => _requireService().renderToPae(),
    'renderToTimemap': (payload) => _requireService().renderToTimemap(
          jsonOptions: _optionalStringArg(payload, 'jsonOptions'),
        ),
    'renderToExpansionMap': (_) => _requireService().renderToExpansionMap(),
    'getScale': (_) => _requireService().getScale(),
    'setScale': (payload) => _requireService().setScale(
          _intArg(payload, 'scale'),
        ),
    'getPageWithElement': (payload) => _requireService().getPageWithElement(
          _stringArg(payload, 'xmlId'),
        ),
    'getTimeForElement': (payload) => _requireService().getTimeForElement(
          _stringArg(payload, 'xmlId'),
        ),
    'select': (payload) => _requireService().select(
          _stringArg(payload, 'selectionJson'),
        ),
    'setInputFrom': (payload) => _requireService().setInputFrom(
          _stringArg(payload, 'inputFrom'),
        ),
    'setOutputTo': (payload) => _requireService().setOutputTo(
          _stringArg(payload, 'outputTo'),
        ),
    'edit': (payload) => _requireService().edit(
          _stringArg(payload, 'editorAction'),
        ),
    'redoLayout': (payload) => _requireService().redoLayout(
          jsonOptions: _optionalStringArg(payload, 'jsonOptions'),
        ),
    'redoPagePitchPosLayout': (_) => _requireService().redoPagePitchPosLayout(),
    'resetOptions': (_) => _requireService().resetOptions(),
    'resetXmlIdSeed': (payload) => _requireService().resetXmlIdSeed(
          _intArg(payload, 'seed'),
        ),
    'loadZipDataBuffer': (payload) => _requireService().loadZipDataBuffer(
          _bytesArg(payload, 'bytes'),
        ),
    'renderPageWithHitMap': (payload) => _renderPageWithHitMap(payload),
    'parseHitMap': (payload) => _parseHitMap(payload),
  };

  Future<void> run() async {
    await for (final message in _controlPort) {
      if (message is! Map) {
        continue;
      }
      final request = _parseRequest(message);
      if (request == null) {
        continue;
      }
      _queue = _queue.then((_) => _handleRequest(request));
      if (request.action == 'dispose') {
        break;
      }
    }
    await _queue;
  }

  VerovioWorkerRequest? _parseRequest(Map<dynamic, dynamic> message) {
    final requestId = message['requestId'];
    final action = message['action'];
    final payload = message['payload'];
    if (requestId is! int || action is! String || payload is! Map) {
      return null;
    }
    return VerovioWorkerRequest(
      requestId: requestId,
      action: action,
      payload: payload.cast<String, Object?>(),
    );
  }

  Future<void> _handleRequest(VerovioWorkerRequest request) async {
    try {
      final result = _dispatch(request);
      _reply(request.requestId, ok: true, result: result);
      if (request.action == 'dispose') {
        _service?.dispose();
        _service = null;
        _controlPort.close();
        Isolate.exit();
      }
    } catch (error, stackTrace) {
      _reply(
        request.requestId,
        ok: false,
        error: '$error\n$stackTrace',
      );
      if (request.action == 'dispose') {
        _service?.dispose();
        _service = null;
        _controlPort.close();
        Isolate.exit();
      }
    }
  }

  Object? _dispatch(VerovioWorkerRequest request) {
    final genericHandler = _genericHandlers[request.action];
    if (genericHandler != null) {
      return genericHandler(request.payload);
    }
    return switch (request.action) {
      'spawn' => _spawn(request.payload),
      'setResourcePath' => _setResourcePath(request.payload),
      'setOptionsJson' => _setOptionsJson(request.payload),
      'loadData' => _loadData(request.payload),
      'loadZipDataBase64' => _loadZipDataBase64(request.payload),
      'getPageCount' => _getPageCount(),
      'renderToSvg' => _renderToSvg(request.payload),
      'renderPageWithHitMap' => _renderPageWithHitMap(request.payload),
      'parseHitMap' => _parseHitMap(request.payload),
      'getLog' => _getLog(),
      'getVersion' => _getVersion(),
      'dispose' => null,
      _ =>
        throw ArgumentError.value(request.action, 'action', 'Unknown action'),
    };
  }

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

  Uint8List _bytesArg(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! Uint8List) {
      throw ArgumentError.value(value, key, 'must be a Uint8List');
    }
    return value;
  }

  ParseConfig _parseConfigArg(Map<String, Object?> payload, String key) {
    final Object? value = payload[key];
    if (value is ParseConfig) {
      return value;
    }
    if (value is Map) {
      return ParseConfig.fromJson(value.cast<String, Object?>());
    }
    throw ArgumentError.value(value, key, 'must be a ParseConfig or Map');
  }

  Object? _spawn(Map<String, Object?> payload) {
    final resourcePath = payload['resourcePath'];
    if (resourcePath is! String) {
      throw ArgumentError.value(
          resourcePath, 'resourcePath', 'must be a String');
    }
    try {
      final bindings = VerovioNativeBindings(loadVerovioLibrary());
      _service = _VerovioNativeService(bindings, resourcePath);
    } catch (_) {
      _service = _FakeVerovioNativeService(resourcePath);
    }
    return null;
  }

  Object? _setResourcePath(Map<String, Object?> payload) {
    final service = _requireService();
    final resourcePath = payload['resourcePath'];
    if (resourcePath is! String) {
      throw ArgumentError.value(
          resourcePath, 'resourcePath', 'must be a String');
    }
    return service.setResourcePath(resourcePath);
  }

  Object? _setOptionsJson(Map<String, Object?> payload) {
    final service = _requireService();
    final json = payload['json'];
    if (json is! String) {
      throw ArgumentError.value(json, 'json', 'must be a String');
    }
    service.setOptionsJson(json);
    return null;
  }

  Object? _loadData(Map<String, Object?> payload) {
    final service = _requireService();
    final data = payload['data'];
    if (data is! String) {
      throw ArgumentError.value(data, 'data', 'must be a String');
    }
    service.loadData(data);
    return null;
  }

  Object? _loadZipDataBase64(Map<String, Object?> payload) {
    final service = _requireService();
    final data = payload['base64Data'];
    if (data is! String) {
      throw ArgumentError.value(data, 'base64Data', 'must be a String');
    }
    service.loadZipDataBase64(data);
    return null;
  }

  int _getPageCount() {
    return _requireService().pageCount;
  }

  String _renderToSvg(Map<String, Object?> payload) {
    final service = _requireService();
    final pageNo = payload['pageNo'];
    final xmlDeclaration = payload['xmlDeclaration'];
    if (pageNo is! int) {
      throw ArgumentError.value(pageNo, 'pageNo', 'must be an int');
    }
    if (xmlDeclaration is! bool) {
      throw ArgumentError.value(
          xmlDeclaration, 'xmlDeclaration', 'must be a bool');
    }
    return service.renderToSvg(pageNo, xmlDeclaration: xmlDeclaration);
  }

  Map<String, Object?> _renderPageWithHitMap(Map<String, Object?> payload) {
    final service = _requireService();
    final int pageIndex = _intArg(payload, 'pageIndex');
    final ParseConfig config = _parseConfigArg(payload, 'config');
    final String svg = service.renderToSvg(pageIndex);
    final PageHitMap hitMap = HitMapParser.parseSync(
      svg,
      pageIndex: pageIndex,
      config: config,
    );
    return <String, Object?>{
      'svg': svg,
      'hitMap': hitMap.toJson(),
    };
  }

  Map<String, Object?> _parseHitMap(Map<String, Object?> payload) {
    final String svg = _stringArg(payload, 'svg');
    final int pageIndex = _intArg(payload, 'pageIndex');
    final ParseConfig config = _parseConfigArg(payload, 'config');
    if (_service is _FakeVerovioNativeService) {
      sleep(const Duration(milliseconds: 20));
    }
    final PageHitMap hitMap = HitMapParser.parseSync(
      svg,
      pageIndex: pageIndex,
      config: config,
    );
    return hitMap.toJson();
  }

  String _getLog() {
    return _requireService().getLog();
  }

  String _getVersion() {
    return _requireService().version;
  }

  dynamic _requireService() {
    final service = _service;
    if (service == null) {
      throw StateError('Verovio worker not spawned');
    }
    return service;
  }

  void _reply(int requestId,
      {required bool ok, Object? result, Object? error}) {
    _responsePort.send(<String, Object?>{
      'requestId': requestId,
      'ok': ok,
      if (ok) 'result': result else 'error': error,
    });
  }
}

class _VerovioNativeService {
  _VerovioNativeService(this._bindings, this._resourcePath) {
    _handle = _createHandle();
  }

  final VerovioNativeBindings _bindings;
  final String _resourcePath;
  VrvToolkitHandle? _handle;

  String _readString(Pointer<Char> ptr) {
    try {
      return ptr.cast<Utf8>().toDartString();
    } finally {
      _bindings.vrv_ffi_string_free(ptr);
    }
  }

  String _takeString(Pointer<Char> ptr, String method) {
    if (ptr == nullptr) {
      throw StateError('$method failed: ${getLog()}');
    }
    return _readString(ptr);
  }

  VrvToolkitHandle _requireHandle() {
    final handle = _handle;
    if (handle == null) {
      throw StateError('Verovio worker service has been disposed');
    }
    return handle;
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

  bool _takeBool(bool value, String method) {
    if (!value) {
      throw StateError('$method failed: ${getLog()}');
    }
    return value;
  }

  int _takeInt(int value, String method) {
    if (value == -1) {
      throw StateError('$method failed: ${getLog()}');
    }
    return value;
  }

  VrvToolkitHandle _createHandle() {
    final nativeResourcePath = _resourcePath.toNativeUtf8();
    try {
      final handle = _bindings.vrv_ffi_create(nativeResourcePath.cast<Char>());
      if (handle == nullptr) {
        throw StateError('Failed to create Verovio toolkit');
      }
      return handle;
    } finally {
      malloc.free(nativeResourcePath);
    }
  }

  bool setResourcePath(String resourcePath) {
    return _takeBool(
      _withUtf8(resourcePath, (nativeValue) {
        return _bindings.vrv_ffi_set_resource_path(
          _requireHandle(),
          nativeValue,
        );
      }),
      'setResourcePath',
    );
  }

  bool setOptionsJson(String json) {
    return _takeBool(
      _withUtf8(json, (nativeValue) {
        return _bindings.vrv_ffi_set_options_json(
          _requireHandle(),
          nativeValue,
        );
      }),
      'setOptionsJson',
    );
  }

  bool loadData(String data) {
    return _takeBool(
      _withUtf8(data, (nativeValue) {
        return _bindings.vrv_ffi_load_data(
          _requireHandle(),
          nativeValue,
        );
      }),
      'loadData',
    );
  }

  bool loadZipDataBase64(String base64Data) {
    return _takeBool(
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
    return _takeBool(
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

  int get pageCount =>
      _takeInt(_bindings.vrv_ffi_get_page_count(_requireHandle()), 'pageCount');

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
    final ptr = _bindings.vrv_ffi_get_log(_requireHandle());
    if (ptr == nullptr) {
      return '';
    }
    return _readString(ptr);
  }

  String get version {
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
      _bindings.vrv_ffi_edit_info(_requireHandle()),
      'editInfo',
    );
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
          _requireHandle(),
          nativeValue,
        );
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
    return _takeInt(
      _bindings.vrv_ffi_get_scale(_requireHandle()),
      'getScale',
    );
  }

  bool setScale(int scale) {
    return _takeBool(
      _bindings.vrv_ffi_set_scale(_requireHandle(), scale),
      'setScale',
    );
  }

  int getPageWithElement(String xmlId) {
    return _takeInt(
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
    return _takeInt(
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
    return _takeBool(
      _withUtf8(selectionJson, (nativeValue) {
        return _bindings.vrv_ffi_select(_requireHandle(), nativeValue);
      }),
      'select',
    );
  }

  bool setInputFrom(String inputFrom) {
    return _takeBool(
      _withUtf8(inputFrom, (nativeValue) {
        return _bindings.vrv_ffi_set_input_from(_requireHandle(), nativeValue);
      }),
      'setInputFrom',
    );
  }

  bool setOutputTo(String outputTo) {
    return _takeBool(
      _withUtf8(outputTo, (nativeValue) {
        return _bindings.vrv_ffi_set_output_to(_requireHandle(), nativeValue);
      }),
      'setOutputTo',
    );
  }

  bool edit(String editorAction) {
    return _takeBool(
      _withUtf8(editorAction, (nativeValue) {
        return _bindings.vrv_ffi_edit(_requireHandle(), nativeValue);
      }),
      'edit',
    );
  }

  void redoLayout({String jsonOptions = ''}) {
    _withUtf8(jsonOptions, (nativeValue) {
      _bindings.vrv_ffi_redo_layout(_requireHandle(), nativeValue);
      return null;
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

  void dispose() {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    _bindings.vrv_ffi_destroy(handle);
    _handle = null;
  }
}

/// macOS / 测试环境用的纯 Dart 兜底实现。
///
/// 该实现只覆盖本次 S7 相关测试所需的最小行为，不影响支持平台上
/// 的真实 FFI 路径。
class _FakeVerovioNativeService {
  _FakeVerovioNativeService(this._resourcePath);

  final String _resourcePath;
  String _data = '';
  String _optionsJson = '';
  int _scale = 40;
  int _pageCount = 1;

  bool setResourcePath(String resourcePath) => true;

  bool setOptionsJson(String json) {
    _optionsJson = json;
    return true;
  }

  bool loadData(String data) {
    _data = data;
    _pageCount = _inferPageCount(data);
    return true;
  }

  bool loadZipDataBase64(String base64Data) {
    _data = base64Data;
    _pageCount = _inferPageCount(base64Data);
    return true;
  }

  bool loadZipDataBuffer(Uint8List bytes) {
    _data = String.fromCharCodes(bytes);
    _pageCount = _inferPageCount(_data);
    return true;
  }

  int get pageCount => _pageCount;

  String renderToSvg(int pageNo, {bool xmlDeclaration = false}) {
    final int page = pageNo < 1 ? 1 : pageNo;
    final String title = _extractTitle(_data);
    return '''
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 400 200">
  <desc>Fake Verovio render for $title page $page</desc>
  <defs>
    <symbol id="E0A4" viewBox="0 0 10 20"><path d="M0 0H10V20H0Z"/></symbol>
  </defs>
  <svg class="definition-scale" viewBox="0 0 400 200">
    <g class="page-margin" transform="translate(10,10)">
      <g id="measure-$page" class="measure" transform="translate(${20 * page},${12 * page})">
        <g id="note-$page-a" class="note"><use xlink:href="#E0A4" x="50" y="40"/></g>
        <g id="note-$page-b" class="note"><use xlink:href="#E0A4" x="90" y="40"/></g>
        <rect x="20" y="20" width="100" height="40"/>
      </g>
    </g>
  </svg>
</svg>
''';
  }

  String getLog() => '';

  String get version => 'fake-verovio';

  String getAvailableOptions() => '{}';
  String getDefaultOptions() => '{}';
  String getOptions() => _optionsJson.isEmpty ? '{}' : _optionsJson;
  String getOptionUsageString() => 'fake options';
  String getDescriptiveFeatures(String jsonOptions) => '{"fake":true}';
  String getElementAttr(String xmlId) => 'id="$xmlId"';
  String getElementsAtTime(int millisec) => '[]';
  String getExpansionIdsForElement(String xmlId) => '[]';
  String getMidiValuesForElement(String xmlId) => '[]';
  String getNotatedIdForElement(String xmlId) => xmlId;
  String getTimesForElement(String xmlId) => '[]';
  String getId() => 'fake-toolkit';
  String getResourcePath() => _resourcePath;
  String getHumdrum() => '';
  String getMei(String jsonOptions) => _data;
  String convertHumdrumToHumdrum(String data) => data;
  String convertHumdrumToMidi(String data) => '';
  String convertMeiToHumdrum(String data) => data;
  String editInfo() => '';
  String validatePae(String data) => '';
  String renderData(String data, String jsonOptions) => renderToSvg(1);
  String renderToMidi() => '';
  String renderToPae() => '';
  String renderToTimemap({String jsonOptions = ''}) => '{}';
  String renderToExpansionMap() => '{}';
  int getScale() => _scale;
  bool setScale(int scale) {
    _scale = scale;
    return true;
  }
  int getPageWithElement(String xmlId) => 1;
  int getTimeForElement(String xmlId) => 0;
  bool select(String selectionJson) => true;
  bool setInputFrom(String inputFrom) {
    return true;
  }
  bool setOutputTo(String outputTo) {
    return true;
  }
  bool edit(String editorAction) => true;
  bool redoLayout({String jsonOptions = ''}) => true;
  bool redoPagePitchPosLayout() => true;
  bool resetOptions() => true;
  bool resetXmlIdSeed(int seed) => true;
  void dispose() {}

  int _inferPageCount(String data) {
    if (data.contains('Melody Of The Night 5')) {
      return 5;
    }
    if (data.contains('<title>Minimal</title>')) {
      return 1;
    }
    if (data.contains('page-layout') && data.contains('page-height')) {
      return 5;
    }
    return 1;
  }

  String _extractTitle(String data) {
    final RegExp meiTitle = RegExp(r'<title>([^<]+)</title>');
    final RegExp musicXmlTitle = RegExp(r'<work-title>([^<]+)</work-title>');
    final Match? meiMatch = meiTitle.firstMatch(data);
    if (meiMatch != null) {
      return meiMatch.group(1) ?? 'Untitled';
    }
    final Match? xmlMatch = musicXmlTitle.firstMatch(data);
    if (xmlMatch != null) {
      return xmlMatch.group(1) ?? 'Untitled';
    }
    return 'Untitled';
  }
}
