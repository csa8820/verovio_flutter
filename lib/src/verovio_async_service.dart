import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:verovio_flutter/src/hit_map/models.dart';
import 'package:verovio_flutter/src/verovio_page_cache.dart';
import 'package:verovio_flutter/src/verovio_isolate_worker.dart';
import 'package:verovio_flutter/src/verovio_resource_manager.dart';
import 'package:verovio_flutter/src/verovio_service.dart';

class _VerovioWorkerClient {
  _VerovioWorkerClient._(
    this._isolate,
    this._controlPort,
    this._responsePort,
  ) {
    _responseSubscription = _responsePort.listen(_handleResponse);
  }

  final Isolate _isolate;
  final SendPort _controlPort;
  final ReceivePort _responsePort;
  late final StreamSubscription<dynamic> _responseSubscription;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  int _nextRequestId = 0;
  bool _disposed = false;

  static Future<_VerovioWorkerClient> connect({
    required String resourcePath,
  }) async {
    final handshakePort = ReceivePort();
    final responsePort = ReceivePort();
    final isolate = await Isolate.spawn(
      verovioIsolateWorkerEntryPoint,
      <String, Object?>{
        'handshakePort': handshakePort.sendPort,
        'responsePort': responsePort.sendPort,
      },
    );
    final controlPort = await handshakePort.first as SendPort;
    final client = _VerovioWorkerClient._(
      isolate,
      controlPort,
      responsePort,
    );
    try {
      await client.sendRaw('spawn', <String, Object?>{
        'resourcePath': resourcePath,
      });
      return client;
    } catch (_) {
      await client.forceDispose();
      rethrow;
    }
  }

  void _handleResponse(dynamic message) {
    if (message is! Map) {
      return;
    }
    final requestId = message['requestId'];
    if (requestId is! int) {
      return;
    }
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete(message.cast<String, Object?>());
  }

  Future<Object?> sendRaw(String action,
      [Map<String, Object?> payload = const <String, Object?>{}]) async {
    if (_disposed) {
      throw StateError('VerovioAsyncService has been disposed');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[requestId] = completer;
    _controlPort.send(<String, Object?>{
      'requestId': requestId,
      'action': action,
      'payload': payload,
    });
    final response = await completer.future;
    if (response['ok'] == true) {
      return response['result'];
    }
    throw VerovioException(
      method: action,
      log: response['error']?.toString() ?? '',
    );
  }

  Future<void> forceDispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('VerovioAsyncService has been disposed'),
        );
      }
    }
    _pending.clear();
    await _responseSubscription.cancel();
    _responsePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    try {
      await sendRaw('dispose');
    } finally {
      await forceDispose();
    }
  }
}

/// Asynchronous wrapper around Verovio backed by a worker isolate.
class VerovioAsyncService {
  VerovioAsyncService._(this._client) : _pageCache = VerovioPageCache();

  final _VerovioWorkerClient _client;
  final VerovioPageCache _pageCache;

  /// Spawns a worker isolate and creates an async Verovio instance.
  static Future<VerovioAsyncService> spawn({
    required String resourcePath,
  }) async {
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
    final client =
        await _VerovioWorkerClient.connect(resourcePath: resourcePath);
    return VerovioAsyncService._(client);
  }

  /// Updates the resource path used by the worker.
  Future<bool> setResourcePath(String resourcePath) async {
    return await _client.sendRaw('setResourcePath', <String, Object?>{
      'resourcePath': resourcePath,
    }) as bool;
  }

  /// Applies a JSON string of Verovio options.
  Future<void> setOptionsJson(String json) async {
    await _client.sendRaw('setOptionsJson', <String, Object?>{'json': json});
  }

  /// Loads input data into the worker.
  Future<void> loadData(String data) async {
    await _client.sendRaw('loadData', <String, Object?>{'data': data});
  }

  /// Loads zipped input data from a Base64 string.
  Future<void> loadZipDataBase64(String base64Data) async {
    await _client.sendRaw('loadZipDataBase64', <String, Object?>{
      'base64Data': base64Data,
    });
  }

  /// Loads zipped input data from raw bytes.
  Future<bool> loadZipDataBuffer(Uint8List bytes) async {
    return await _client.sendRaw('loadZipDataBuffer', <String, Object?>{
      'bytes': bytes,
    }) as bool;
  }

  /// Returns the number of pages currently available.
  Future<int> get pageCount async {
    return await _client.sendRaw('getPageCount') as int;
  }

  /// Renders the requested page as SVG markup.
  Future<String> renderToSvg(int pageNo, {bool xmlDeclaration = false}) async {
    return await _client.sendRaw('renderToSvg', <String, Object?>{
      'pageNo': pageNo,
      'xmlDeclaration': xmlDeclaration,
    }) as String;
  }

  /// 渲染一页并解析出 HitMap，一次 worker round-trip 完成。
  Future<({String svg, PageHitMap hitMap})> renderPageWithHitMap(
    int pageIndex, {
    ParseConfig config = const ParseConfig.defaultForInteractive(),
  }) async {
    final int configHash = config.configHash;
    final PageCacheEntry? cached = _pageCache.getPageEntry(pageIndex, configHash);
    if (cached != null && cached.hitMap != null) {
      return (
        svg: cached.svg,
        hitMap: cached.hitMap!,
      );
    }
    if (cached != null && cached.hitMap == null) {
      final PageHitMap hitMap = await parseHitMap(
        cached.svg,
        pageIndex: pageIndex,
        config: config,
      );
      return (svg: cached.svg, hitMap: hitMap);
    }

    final Object? response = await _client.sendRaw(
      'renderPageWithHitMap',
      <String, Object?>{
        'pageIndex': pageIndex,
        'config': config.toJson(),
      },
    );
    final Map<String, Object?> responseMap = (response as Map).cast<String, Object?>();
    final String svg = responseMap['svg'] as String;
    final PageHitMap hitMap = _decodeHitMap(responseMap['hitMap']);
    _pageCache.putPageEntry(
      pageIndex: pageIndex,
      configHash: configHash,
      svg: svg,
      hitMap: hitMap,
    );
    return (svg: svg, hitMap: hitMap);
  }

  /// 仅解析已有 SVG 字符串（业务自己缓存了 SVG 时用）。
  Future<PageHitMap> parseHitMap(
    String svg, {
    int pageIndex = 0,
    ParseConfig config = const ParseConfig.defaultForInteractive(),
  }) async {
    final Object? response = await _client.sendRaw(
      'parseHitMap',
      <String, Object?>{
        'svg': svg,
        'pageIndex': pageIndex,
        'config': config.toJson(),
      },
    );
    final PageHitMap hitMap = _decodeHitMap(response);
    _pageCache.putPageEntry(
      pageIndex: pageIndex,
      configHash: config.configHash,
      svg: svg,
      hitMap: hitMap,
    );
    return hitMap;
  }

  /// Returns the current Verovio log output.
  Future<String> getLog() async {
    return await _client.sendRaw('getLog') as String;
  }

  /// Returns the native Verovio version string.
  Future<String> getVersion() async {
    return await _client.sendRaw('getVersion') as String;
  }

  /// Returns the list of available options as JSON.
  Future<String> getAvailableOptions() async {
    return await _client.sendRaw('getAvailableOptions') as String;
  }

  /// Returns the default options as JSON.
  Future<String> getDefaultOptions() async {
    return await _client.sendRaw('getDefaultOptions') as String;
  }

  /// Returns the current option state as JSON.
  Future<String> getOptions() async {
    return await _client.sendRaw('getOptions') as String;
  }

  /// Returns a human-readable description of the available options.
  Future<String> getOptionUsageString() async {
    return await _client.sendRaw('getOptionUsageString') as String;
  }

  /// Returns a description of the features enabled by [jsonOptions].
  Future<String> getDescriptiveFeatures(String jsonOptions) async {
    return await _client.sendRaw('getDescriptiveFeatures', <String, Object?>{
      'jsonOptions': jsonOptions,
    }) as String;
  }

  /// Returns the attributes for the element identified by [xmlId].
  Future<String> getElementAttr(String xmlId) async {
    return await _client.sendRaw('getElementAttr', <String, Object?>{
      'xmlId': xmlId,
    }) as String;
  }

  /// Returns the elements active at the given time in milliseconds.
  Future<String> getElementsAtTime(int millisec) async {
    return await _client.sendRaw('getElementsAtTime', <String, Object?>{
      'millisec': millisec,
    }) as String;
  }

  /// Returns the expansion IDs for the element identified by [xmlId].
  Future<String> getExpansionIdsForElement(String xmlId) async {
    return await _client.sendRaw('getExpansionIdsForElement', <String, Object?>{
      'xmlId': xmlId,
    }) as String;
  }

  /// Returns MIDI values for the element identified by [xmlId].
  Future<String> getMidiValuesForElement(String xmlId) async {
    return await _client.sendRaw('getMidiValuesForElement', <String, Object?>{
      'xmlId': xmlId,
    }) as String;
  }

  /// Returns the notated ID for the element identified by [xmlId].
  Future<String> getNotatedIdForElement(String xmlId) async {
    return await _client.sendRaw('getNotatedIdForElement', <String, Object?>{
      'xmlId': xmlId,
    }) as String;
  }

  /// Returns the times associated with the element identified by [xmlId].
  Future<String> getTimesForElement(String xmlId) async {
    return await _client.sendRaw('getTimesForElement', <String, Object?>{
      'xmlId': xmlId,
    }) as String;
  }

  /// Returns the toolkit instance ID.
  Future<String> getId() async {
    return await _client.sendRaw('getId') as String;
  }

  /// Returns the currently configured resource path.
  Future<String> getResourcePath() async {
    return await _client.sendRaw('getResourcePath') as String;
  }

  /// Returns the current score as Humdrum text.
  Future<String> getHumdrum() async {
    return await _client.sendRaw('getHumdrum') as String;
  }

  /// Returns the current score as MEI using [jsonOptions].
  Future<String> getMei(String jsonOptions) async {
    return await _client.sendRaw('getMei', <String, Object?>{
      'jsonOptions': jsonOptions,
    }) as String;
  }

  /// Converts Humdrum input to normalized Humdrum output.
  Future<String> convertHumdrumToHumdrum(String data) async {
    return await _client.sendRaw('convertHumdrumToHumdrum', <String, Object?>{
      'data': data,
    }) as String;
  }

  /// Converts Humdrum input to Base64-encoded MIDI data.
  Future<String> convertHumdrumToMidi(String data) async {
    return await _client.sendRaw('convertHumdrumToMidi', <String, Object?>{
      'data': data,
    }) as String;
  }

  /// Converts Humdrum input directly to MIDI bytes.
  Future<Uint8List> convertHumdrumToMidiBytes(String data) async {
    return base64Decode(await convertHumdrumToMidi(data));
  }

  /// Converts MEI input to Humdrum text.
  Future<String> convertMeiToHumdrum(String data) async {
    return await _client.sendRaw('convertMeiToHumdrum', <String, Object?>{
      'data': data,
    }) as String;
  }

  /// Returns the current editor information string.
  Future<String> editInfo() async {
    return await _client.sendRaw('editInfo') as String;
  }

  /// Validates PAE input and returns the result string.
  Future<String> validatePae(String data) async {
    return await _client.sendRaw('validatePae', <String, Object?>{
      'data': data,
    }) as String;
  }

  /// Renders arbitrary input data using the provided JSON options.
  Future<String> renderData(String data, String jsonOptions) async {
    return await _client.sendRaw('renderData', <String, Object?>{
      'data': data,
      'jsonOptions': jsonOptions,
    }) as String;
  }

  /// Renders the current score to Base64-encoded MIDI data.
  Future<String> renderToMidi() async {
    return await _client.sendRaw('renderToMidi') as String;
  }

  /// Renders the current score to MIDI bytes.
  Future<Uint8List> renderToMidiBytes() async {
    return base64Decode(await renderToMidi());
  }

  /// Renders the current score to PAE text.
  Future<String> renderToPae() async {
    return await _client.sendRaw('renderToPae') as String;
  }

  /// Renders the current score to a time map.
  Future<String> renderToTimemap({String jsonOptions = ''}) async {
    return await _client.sendRaw('renderToTimemap', <String, Object?>{
      'jsonOptions': jsonOptions,
    }) as String;
  }

  /// Renders the current score to an expansion map.
  Future<String> renderToExpansionMap() async {
    return await _client.sendRaw('renderToExpansionMap') as String;
  }

  /// Returns the current engraving scale.
  Future<int> getScale() async {
    return await _client.sendRaw('getScale') as int;
  }

  /// Sets the engraving scale.
  Future<bool> setScale(int scale) async {
    return await _client.sendRaw('setScale', <String, Object?>{
      'scale': scale,
    }) as bool;
  }

  /// Returns the page that contains the element identified by [xmlId].
  Future<int> getPageWithElement(String xmlId) async {
    return await _client.sendRaw('getPageWithElement', <String, Object?>{
      'xmlId': xmlId,
    }) as int;
  }

  /// Returns the time position for the element identified by [xmlId].
  Future<int> getTimeForElement(String xmlId) async {
    return await _client.sendRaw('getTimeForElement', <String, Object?>{
      'xmlId': xmlId,
    }) as int;
  }

  /// Applies a selection described by [selectionJson].
  Future<bool> select(String selectionJson) async {
    return await _client.sendRaw('select', <String, Object?>{
      'selectionJson': selectionJson,
    }) as bool;
  }

  /// Sets the current input format.
  Future<bool> setInputFrom(String inputFrom) async {
    return await _client.sendRaw('setInputFrom', <String, Object?>{
      'inputFrom': inputFrom,
    }) as bool;
  }

  /// Sets the current output format.
  Future<bool> setOutputTo(String outputTo) async {
    return await _client.sendRaw('setOutputTo', <String, Object?>{
      'outputTo': outputTo,
    }) as bool;
  }

  /// Applies an editor action string.
  Future<bool> edit(String editorAction) async {
    return await _client.sendRaw('edit', <String, Object?>{
      'editorAction': editorAction,
    }) as bool;
  }

  /// Recomputes the layout using optional JSON options.
  Future<void> redoLayout({String jsonOptions = ''}) async {
    await _client.sendRaw('redoLayout', <String, Object?>{
      'jsonOptions': jsonOptions,
    });
  }

  /// Recomputes the page pitch-position layout.
  Future<void> redoPagePitchPosLayout() async {
    await _client.sendRaw('redoPagePitchPosLayout');
  }

  /// Resets all options to their defaults.
  Future<void> resetOptions() async {
    await _client.sendRaw('resetOptions');
  }

  /// Resets the XML ID seed to [seed].
  Future<void> resetXmlIdSeed(int seed) async {
    await _client.sendRaw('resetXmlIdSeed', <String, Object?>{
      'seed': seed,
    });
  }

  /// Releases the worker isolate and native toolkit resources.
  Future<void> dispose() async {
    await _client.dispose();
  }

  PageHitMap _decodeHitMap(Object? response) {
    if (response is PageHitMap) {
      return response;
    }
    if (response is Map) {
      return PageHitMap.fromJson(response.cast<String, Object?>());
    }
    throw StateError('Unexpected hit map response: $response');
  }
}
