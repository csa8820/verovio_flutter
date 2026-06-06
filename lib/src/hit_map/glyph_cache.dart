import 'dart:collection';
import 'dart:developer' as developer;

import 'package:verovio_flutter/src/hit_map/geometry.dart';
import 'package:verovio_flutter/src/hit_map/models_data.dart';
import 'package:verovio_flutter/src/hit_map/path_bbox.dart';

/// SMuFL 字形 bbox 缓存。
///
/// 注意：此缓存**非线程安全**，仅供同一 isolate 内的单页/多页解析复用。
class GlyphBBoxCache {
  GlyphBBoxCache() : _local = <String, RectD>{};

  /// 当前文档（单页解析）的字形缓存。
  ///
  /// key 是 symbol 的 id（已去掉前导 `#`）。
  final Map<String, RectD> _local;

  /// 跨页/跨文档的持久缓存。
  ///
  /// key 是 `"$fontHash:$glyphId"`。
  static final LinkedHashMap<String, RectD> _global =
      LinkedHashMap<String, RectD>();

  static const int _defaultGlobalMaxEntries = 2000;

  /// 仅测试用：可临时调整全局缓存上限，便于验证 LRU 淘汰。
  static int globalMaxEntriesForTesting = _defaultGlobalMaxEntries;

  /// 本页查表：href 可以是 `"#E0A4"` 或 `"E0A4"`。
  RectD? lookup(String href) {
    return _local[_normalizeId(href)];
  }

  /// 写入本页缓存。
  void put(String id, RectD bbox) {
    _local[_normalizeId(id)] = bbox;
  }

  /// 跨文档全局查表（按字体哈希命名空间）。
  static RectD? lookupGlobal(String fontHash, String id) {
    final String key = _globalKey(fontHash, id);
    final RectD? value = _global.remove(key);
    if (value != null) {
      // 命中时按标准 LRU 语义移动到队尾。
      _global[key] = value;
    }
    return value;
  }

  /// 跨文档全局写入（带 LRU 淘汰）。
  static void putGlobal(String fontHash, String id, RectD bbox) {
    final String key = _globalKey(fontHash, id);
    // 先移除旧值，再写回末尾，实现“最近使用”语义。
    _global.remove(key);
    _global[key] = bbox;

    if (_global.length > globalMaxEntriesForTesting) {
      final String oldestKey = _global.keys.first;
      _global.remove(oldestKey);
    }
  }

  /// 本页缓存条数（监控用）。
  int get localSize => _local.length;

  /// 全局缓存条数（监控用）。
  static int get globalSize => _global.length;

  /// 仅测试用：清空全局缓存。
  static void clearGlobal() {
    _global.clear();
  }

  /// 仅测试用：恢复全局缓存上限。
  static void resetGlobalMaxEntriesForTesting() {
    globalMaxEntriesForTesting = _defaultGlobalMaxEntries;
  }

  static String _normalizeId(String id) {
    return id.startsWith('#') ? id.substring(1) : id;
  }

  static String _globalKey(String fontHash, String id) {
    return '$fontHash:${_normalizeId(id)}';
  }
}

/// 从 `<defs>` 收到的 symbol 信息 + 内部 path 字符串 → 计算 bbox 并写入 cache。
///
/// - 若 `symbolViewBox` 存在，优先使用它；这是作者直接给出的精确边界。
/// - 否则回退到 `pathD` 的几何 bbox 求解。
/// - 若两者都缺失，则写入 `RectD.zero` 作为兜底。
RectD populateGlyphFromSymbol({
  required String id,
  required String? symbolViewBox,
  required String? pathD,
  required PathBBoxSolver solver,
  required HitMapPathBBoxMode mode,
  required GlyphBBoxCache cache,
}) {
  final RectD? cached = cache.lookup(id);
  if (cached != null) {
    return cached;
  }

  if (symbolViewBox != null && symbolViewBox.trim().isNotEmpty) {
    final RectD? rect = _parseViewBox(symbolViewBox);
    if (rect != null) {
      cache.put(id, rect);
      return rect;
    }

    _logWarning(
      'glyph bbox viewBox 解析失败：id=$id，已回退到 path bbox 或 RectD.zero。',
    );
  }

  if (pathD != null && pathD.trim().isNotEmpty) {
    final RectD rect = solver.solveToRectD(pathD, mode);
    cache.put(id, rect);
    return rect;
  }

  _logWarning('glyph bbox 缺失：id=$id，symbol viewBox 与 path 均为空。');
  cache.put(id, RectD.zero);
  return RectD.zero;
}

RectD? _parseViewBox(String viewBox) {
  final List<String> parts = viewBox
      .trim()
      .split(RegExp(r'\s+'))
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length != 4) {
    return null;
  }
  final double? x = double.tryParse(parts[0]);
  final double? y = double.tryParse(parts[1]);
  final double? w = double.tryParse(parts[2]);
  final double? h = double.tryParse(parts[3]);
  if (x == null || y == null || w == null || h == null) {
    return null;
  }
  return RectD.fromLTWH(x, y, w, h);
}

void _logWarning(String message) {
  // 这里仅用于解析过程中的兜底告警，不影响主流程。
  developer.log(
    message,
    name: 'glyph_cache',
    level: 900,
  );
}
