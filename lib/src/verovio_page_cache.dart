import 'dart:collection';

import 'package:verovio_flutter/src/hit_map/models.dart';

/// 页面缓存条目。
class PageCacheEntry {
  const PageCacheEntry({
    required this.svg,
    this.hitMap,
  });

  /// 页面 SVG。
  final String svg;

  /// 该页对应的 HitMap；仅渲染未解析时可为 null。
  final PageHitMap? hitMap;
}

/// Simple in-memory cache for rendered Verovio pages.
class VerovioPageCache {
  /// Creates a cache with the given maximum [capacity].
  VerovioPageCache({int capacity = 32}) : assert(capacity > 0) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be greater than 0');
    }
    _capacity = capacity;
  }

  late final int _capacity;
  final LinkedHashMap<String, PageCacheEntry> _entries =
      LinkedHashMap<String, PageCacheEntry>();

  /// Returns a cached page render or stores a fresh render result.
  Future<String> getOrRender({
    required String data,
    required String optionsJson,
    required int pageNo,
    required Future<String> Function() render,
  }) async {
    final key = _legacyCacheKey(data, optionsJson, pageNo);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached.svg;
    }

    final svg = await render();
    _put(key, PageCacheEntry(svg: svg));
    return svg;
  }

  /// 获取 HitMap 页面缓存。
  PageCacheEntry? getPageEntry(int pageIndex, int configHash) {
    final String key = _pageCacheKey(pageIndex, configHash);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
    }
    return cached;
  }

  /// 写入 HitMap 页面缓存。
  void putPageEntry({
    required int pageIndex,
    required int configHash,
    required String svg,
    PageHitMap? hitMap,
  }) {
    final String key = _pageCacheKey(pageIndex, configHash);
    _put(key, PageCacheEntry(svg: svg, hitMap: hitMap));
  }

  /// 仅写入 SVG 的 HitMap 页面缓存。
  void putPageSvgOnly({
    required int pageIndex,
    required int configHash,
    required String svg,
  }) {
    putPageEntry(
      pageIndex: pageIndex,
      configHash: configHash,
      svg: svg,
      hitMap: null,
    );
  }

  /// Clears all cached render results.
  void invalidateAll() {
    _entries.clear();
  }

  /// Returns the number of cached entries.
  int get length => _entries.length;

  int _fnv1a64(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h = (h ^ c) * 0x100000001b3;
      h &= 0xffffffffffffffff;
    }
    return h;
  }

  void _put(String key, PageCacheEntry entry) {
    _entries[key] = entry;
    while (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  String _legacyCacheKey(String data, String options, int page) =>
      '${_fnv1a64(data).toRadixString(16)}:'
      '${_fnv1a64(options).toRadixString(16)}:$page';

  String _pageCacheKey(int pageIndex, int configHash) =>
      'page:$pageIndex:$configHash';
}
