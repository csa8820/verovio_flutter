import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:verovio_flutter/src/hit_map/models.dart';
import 'package:verovio_flutter/src/hit_map/spatial_index.dart';

const int kBruteForceThreshold = 64;

/// 仅测试使用：统计是否真的走到了 R-tree 查询路径。
@visibleForTesting
int debugRTreePointQueryCount = 0;

/// 仅测试使用：统计是否真的走到了 R-tree 查询路径。
@visibleForTesting
int debugRTreeRectQueryCount = 0;

final Expando<Map<ElementHit, int>> _orderIndexCache =
    Expando<Map<ElementHit, int>>('hit_map_order_index');

/// 在 HitMap 中查询包含指定点的最上层元素。
///
/// 坐标系：svgPoint 必须是 SVG viewBox 坐标，调用方负责屏幕 → SVG 反变换。
///
/// 命中策略：
/// - 多个候选时按"最深栈"返回（DFS 顺序最晚 emit 的，即最内层 / 视觉最上层）
/// - 利用 PageHitMap.byId 是 LinkedHashMap 插入顺序为 DFS 后序的特性
///
/// 性能：
/// - hitMap.rTree != null 时 O(log n + k)
/// - 否则 O(n) 暴力扫
/// - n < kBruteForceThreshold(=64) 时无视 rTree 强制暴力（避免索引开销大于收益）
///
/// types 过滤：只考虑 type 在该集合内的元素；null 表示不过滤
ElementHit? hitTestPoint(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
  bool topMost = true,
}) {
  if (!_isFiniteOffset(svgPoint) || hitMap.byId.isEmpty) {
    return null;
  }

  if (_useBruteForce(hitMap)) {
    return _hitTestPointBruteForce(
      hitMap,
      svgPoint,
      types: types,
      topMost: topMost,
    );
  }

  final SpatialIndex? rTree = hitMap.rTree;
  if (rTree == null) {
    return _hitTestPointBruteForce(
      hitMap,
      svgPoint,
      types: types,
      topMost: topMost,
    );
  }

  debugRTreePointQueryCount++;
  final Map<ElementHit, int> orderIndex = _orderIndex(hitMap);
  ElementHit? best;
  int bestOrder = topMost ? -1 : 1 << 62;

  for (final ElementHit hit in rTree.queryPoint(svgPoint)) {
    if (!_matchesTypes(hit, types)) {
      continue;
    }
    final int order = orderIndex[hit] ?? -1;
    if (best == null) {
      best = hit;
      bestOrder = order;
      continue;
    }

    if (topMost ? order > bestOrder : order < bestOrder) {
      best = hit;
      bestOrder = order;
    }
  }

  return best;
}

/// 在 HitMap 中查询所有与给定矩形相交（或完全包含）的元素。
List<ElementHit> hitTestRect(
  PageHitMap hitMap,
  Rect svgRect, {
  Set<String>? types,
  bool fullyContained = false,
}) {
  if (hitMap.byId.isEmpty) {
    return List<ElementHit>.empty(growable: true);
  }

  final Rect normalized = _normalizeRect(svgRect);
  if (!_isFiniteRect(normalized)) {
    return List<ElementHit>.empty(growable: true);
  }

  if (_useBruteForce(hitMap)) {
    return _hitTestRectBruteForce(
      hitMap,
      normalized,
      types: types,
      fullyContained: fullyContained,
    );
  }

  final SpatialIndex? rTree = hitMap.rTree;
  if (rTree == null) {
    return _hitTestRectBruteForce(
      hitMap,
      normalized,
      types: types,
      fullyContained: fullyContained,
    );
  }

  debugRTreeRectQueryCount++;
  final Set<ElementHit> candidates = Set<ElementHit>.identity();
  for (final ElementHit hit in rTree.queryRect(
    normalized,
    fullyContained: fullyContained,
  )) {
    if (_matchesTypes(hit, types)) {
      candidates.add(hit);
    }
  }
  if (candidates.isEmpty) {
    return List<ElementHit>.empty(growable: true);
  }

  final List<ElementHit> hits = candidates.toList(growable: true);
  if (hits.length > 1) {
    _sortByOrder(hits, hitMap);
  }
  return hits;
}

/// 同 hitTestPoint，但返回所有命中（不只是最上层），按 DFS 后序排列
List<ElementHit> hitTestPointAll(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
}) {
  if (!_isFiniteOffset(svgPoint) || hitMap.byId.isEmpty) {
    return List<ElementHit>.empty(growable: true);
  }

  if (_useBruteForce(hitMap) || hitMap.rTree == null) {
    final List<ElementHit> hits = List<ElementHit>.empty(growable: true);
    for (final ElementHit hit in hitMap.byType) {
      if (_matchesTypes(hit, types) && hit.bbox.contains(svgPoint)) {
        hits.add(hit);
      }
    }
    return hits;
  }

  debugRTreePointQueryCount++;
  final List<ElementHit> hits = List<ElementHit>.empty(growable: true);
  for (final ElementHit hit in hitMap.rTree!.queryPoint(svgPoint)) {
    if (_matchesTypes(hit, types)) {
      hits.add(hit);
    }
  }
  if (hits.length > 1) {
    _sortByOrder(hits, hitMap);
  }
  return hits;
}

/// 在 HitMap 中查询距 [svgPoint] 最近的元素（以点到 bbox 最短距离衡量）。
///
/// 与 [hitTestPoint] 不同，本函数在点未落入任何 bbox 时仍会返回结果，
/// 适合"点击任意位置吸附到最近音符"的场景。
///
/// - 优先走 R-tree branch-and-bound，均摊 O(log n)
/// - 元素数 < [kBruteForceThreshold] 或无索引时退化为 O(n) 暴力
/// - [types] 为 null 时不过滤；hitMap 为空或无满足条件的元素时返回 null
ElementHit? snapToNearest(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
}) {
  if (!_isFiniteOffset(svgPoint) || hitMap.byId.isEmpty) return null;

  if (!_useBruteForce(hitMap) && hitMap.rTree != null) {
    return hitMap.rTree!.queryNearest(svgPoint, types: types);
  }

  return _snapNearestBruteForce(hitMap, svgPoint, types: types);
}

ElementHit? _snapNearestBruteForce(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
}) {
  ElementHit? best;
  double bestDist = double.infinity;
  final double px = svgPoint.dx;
  final double py = svgPoint.dy;
  for (final ElementHit hit in hitMap.byType) {
    if (!_matchesTypes(hit, types)) continue;
    final Rect r = hit.bbox;
    final double dx = px < r.left ? r.left - px : (px > r.right ? px - r.right : 0.0);
    final double dy = py < r.top ? r.top - py : (py > r.bottom ? py - r.bottom : 0.0);
    final double d = dx * dx + dy * dy; // 用平方距离比较，省去 sqrt
    if (d < bestDist) {
      bestDist = d;
      best = hit;
    }
  }
  return best;
}

bool _useBruteForce(PageHitMap hitMap) {
  return hitMap.byId.length < kBruteForceThreshold;
}

bool _matchesTypes(ElementHit hit, Set<String>? types) {
  return types?.contains(hit.type) ?? true;
}

bool _isFiniteOffset(Offset point) {
  return point.dx.isFinite && point.dy.isFinite;
}

bool _isFiniteRect(Rect rect) {
  return rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite;
}

Rect _normalizeRect(Rect rect) {
  final double left = math.min(rect.left, rect.right);
  final double right = math.max(rect.left, rect.right);
  final double top = math.min(rect.top, rect.bottom);
  final double bottom = math.max(rect.top, rect.bottom);
  return Rect.fromLTRB(left, top, right, bottom);
}

ElementHit? _hitTestPointBruteForce(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
  required bool topMost,
}) {
  final List<ElementHit> hits = hitMap.byType;
  if (topMost) {
    for (int i = hits.length - 1; i >= 0; i--) {
      final ElementHit hit = hits[i];
      if (_matchesTypes(hit, types) && hit.bbox.contains(svgPoint)) {
        return hit;
      }
    }
    return null;
  }

  for (final ElementHit hit in hits) {
    if (_matchesTypes(hit, types) && hit.bbox.contains(svgPoint)) {
      return hit;
    }
  }
  return null;
}

List<ElementHit> _hitTestRectBruteForce(
  PageHitMap hitMap,
  Rect svgRect, {
  Set<String>? types,
  required bool fullyContained,
}) {
  final List<ElementHit> hits = List<ElementHit>.empty(growable: true);
  for (final ElementHit hit in hitMap.byType) {
    if (!_matchesTypes(hit, types)) {
      continue;
    }
    if (fullyContained) {
      if (_containsRect(svgRect, hit.bbox)) {
        hits.add(hit);
      }
    } else if (hit.bbox.overlaps(svgRect)) {
      hits.add(hit);
    }
  }
  return hits;
}

bool _containsRect(Rect outer, Rect inner) {
  return inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;
}

Map<ElementHit, int> _orderIndex(PageHitMap hitMap) {
  final Map<ElementHit, int>? cached = _orderIndexCache[hitMap];
  if (cached != null) {
    return cached;
  }

  final Map<ElementHit, int> order = Map<ElementHit, int>.identity();
  int index = 0;
  for (final ElementHit hit in hitMap.byType) {
    order[hit] = index++;
  }
  _orderIndexCache[hitMap] = order;
  return order;
}

void _sortByOrder(List<ElementHit> hits, PageHitMap hitMap) {
  final Map<ElementHit, int> order = _orderIndex(hitMap);
  hits.sort((ElementHit a, ElementHit b) {
    final int ao = order[a] ?? -1;
    final int bo = order[b] ?? -1;
    return ao.compareTo(bo);
  });
}
