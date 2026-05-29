import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:verovio_flutter/src/hit_map/models.dart';

/// 静态 STR-packed R-tree。
///
/// 适合 HitMap 这种“一次构建、只读查询”的场景。
class SpatialIndex {
  SpatialIndex._(this._root, this._size);

  /// 默认每个节点最多子项数。
  static const int _maxChildrenPerNode = 16;

  /// 仅测试：统计构建调用次数，便于验证 buildSpatialIndex 开关。
  @visibleForTesting
  static int buildInvocationCountForTesting = 0;

  late final _Node _root;
  final int _size;

  /// 索引中命中的元素数量。
  int get size => _size;

  /// 仅测试使用：直接观察根节点结构。
  @visibleForTesting
  dynamic get debugRoot => _root;

  /// 使用一组 [ElementHit] 一次性构建索引。
  factory SpatialIndex.build(
    List<ElementHit> hits, {
    int maxChildren = _maxChildrenPerNode,
  }) {
    buildInvocationCountForTesting++;

    if (hits.isEmpty) {
      throw ArgumentError.value(hits, 'hits', '空 hits 不允许构建空间索引');
    }
    if (maxChildren <= 0) {
      throw ArgumentError.value(
        maxChildren,
        'maxChildren',
        'maxChildren 必须大于 0',
      );
    }

    final List<ElementHit> items = List<ElementHit>.of(hits);
    final _Node root = _packHits(items, maxChildren);
    return SpatialIndex._(root, items.length);
  }

  /// 查询包含指定点的所有元素。
  Iterable<ElementHit> queryPoint(Offset svgPoint) sync* {
    yield* _queryPointFromNode(_root, svgPoint);
  }

  /// 查询距 [point] 最近的元素（以点到 bbox 的最短距离衡量）。
  ///
  /// [types] 为 null 时不过滤类型。
  /// 使用 branch-and-bound 剪枝，均摊复杂度 O(log n)。
  /// 若无满足条件的元素，返回 null。
  ElementHit? queryNearest(Offset point, {Set<String>? types}) {
    final _NNState state = _NNState(point.dx, point.dy, types);
    _searchNearest(_root, state);
    return state.best;
  }

  /// 查询与给定矩形相交的元素。
  ///
  /// [fullyContained] 为 `true` 时，只返回完全被 [svgRect] 包含的元素。
  Iterable<ElementHit> queryRect(
    Rect svgRect, {
    bool fullyContained = false,
  }) sync* {
    yield* _queryRectFromNode(_root, svgRect, fullyContained);
  }

  /// 返回索引深度与每层节点数。
  ///
  /// [nodesPerLevel] 按“自下而上”排列：叶子层在前，根节点在最后。
  ({int depth, List<int> nodesPerLevel}) stats() {
    final List<int> perLevelTopDown = <int>[];
    void visit(_Node node, int depth) {
      if (depth == perLevelTopDown.length) {
        perLevelTopDown.add(0);
      }
      perLevelTopDown[depth]++;
      final List<_Node>? children = node.children;
      if (children == null) {
        return;
      }
      for (final _Node child in children) {
        visit(child, depth + 1);
      }
    }

    visit(_root, 0);
    return (
      depth: perLevelTopDown.length,
      nodesPerLevel: perLevelTopDown.reversed.toList(growable: false),
    );
  }

  Iterable<ElementHit> _queryPointFromNode(_Node node, Offset p) sync* {
    if (p.dx < node.minX ||
        p.dx > node.maxX ||
        p.dy < node.minY ||
        p.dy > node.maxY) {
      return;
    }

    final List<ElementHit>? hits = node.hits;
    if (hits != null) {
      for (final ElementHit hit in hits) {
        if (hit.bbox.contains(p)) {
          yield hit;
        }
      }
      return;
    }

    for (final _Node child in node.children!) {
      yield* _queryPointFromNode(child, p);
    }
  }

  Iterable<ElementHit> _queryRectFromNode(
    _Node node,
    Rect svgRect,
    bool fullyContained,
  ) sync* {
    if (!_intersects(node, svgRect)) {
      return;
    }

    final List<ElementHit>? hits = node.hits;
    if (hits != null) {
      for (final ElementHit hit in hits) {
        if (fullyContained) {
          if (_containsRect(svgRect, hit.bbox)) {
            yield hit;
          }
        } else if (hit.bbox.overlaps(svgRect)) {
          yield hit;
        }
      }
      return;
    }

    for (final _Node child in node.children!) {
      yield* _queryRectFromNode(child, svgRect, fullyContained);
    }
  }

  static bool _intersects(_Node node, Rect rect) {
    return !(rect.right < node.minX ||
        rect.left > node.maxX ||
        rect.bottom < node.minY ||
        rect.top > node.maxY);
  }

  static bool _containsRect(Rect outer, Rect inner) {
    return inner.left >= outer.left &&
        inner.top >= outer.top &&
        inner.right <= outer.right &&
        inner.bottom <= outer.bottom;
  }

  static _Node _packHits(List<ElementHit> hits, int maxChildren) {
    final int n = hits.length;
    final int sliceCount = math.max(1, math.sqrt(n / maxChildren).ceil());
    final int sliceSize = (n / sliceCount).ceil();

    hits.sort(_compareHitByCenterX);

    final List<_Node> nodes = <_Node>[];
    for (int sliceStart = 0; sliceStart < n; sliceStart += sliceSize) {
      final int sliceEnd = math.min(sliceStart + sliceSize, n);
      final List<ElementHit> slice = hits.sublist(sliceStart, sliceEnd);
      slice.sort(_compareHitByCenterY);
      for (int groupStart = 0;
          groupStart < slice.length;
          groupStart += maxChildren) {
        final int groupEnd = math.min(groupStart + maxChildren, slice.length);
        final List<ElementHit> group = slice.sublist(groupStart, groupEnd);
        final Rect aabb = _computeHitAabb(group);
        nodes.add(
            _Node.leaf(group, aabb.left, aabb.top, aabb.right, aabb.bottom));
      }
    }

    if (nodes.length == 1) {
      return nodes.single;
    }
    return _packNodes(nodes, maxChildren);
  }

  static _Node _packNodes(List<_Node> nodes, int maxChildren) {
    final int n = nodes.length;
    final int sliceCount = math.max(1, math.sqrt(n / maxChildren).ceil());
    final int sliceSize = (n / sliceCount).ceil();

    nodes.sort(_compareNodeByCenterX);

    final List<_Node> nextLevel = <_Node>[];
    for (int sliceStart = 0; sliceStart < n; sliceStart += sliceSize) {
      final int sliceEnd = math.min(sliceStart + sliceSize, n);
      final List<_Node> slice = nodes.sublist(sliceStart, sliceEnd);
      slice.sort(_compareNodeByCenterY);
      for (int groupStart = 0;
          groupStart < slice.length;
          groupStart += maxChildren) {
        final int groupEnd = math.min(groupStart + maxChildren, slice.length);
        final List<_Node> group = slice.sublist(groupStart, groupEnd);
        final Rect aabb = _computeNodeAabb(group);
        nextLevel.add(
          _Node.branch(group, aabb.left, aabb.top, aabb.right, aabb.bottom),
        );
      }
    }

    return nextLevel.length == 1
        ? nextLevel.single
        : _packNodes(nextLevel, maxChildren);
  }

  static Rect _computeHitAabb(List<ElementHit> hits) {
    double minX = hits.first.bbox.left;
    double minY = hits.first.bbox.top;
    double maxX = hits.first.bbox.right;
    double maxY = hits.first.bbox.bottom;
    for (int i = 1; i < hits.length; i++) {
      final Rect bbox = hits[i].bbox;
      if (bbox.left < minX) minX = bbox.left;
      if (bbox.top < minY) minY = bbox.top;
      if (bbox.right > maxX) maxX = bbox.right;
      if (bbox.bottom > maxY) maxY = bbox.bottom;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static Rect _computeNodeAabb(List<_Node> nodes) {
    double minX = nodes.first.minX;
    double minY = nodes.first.minY;
    double maxX = nodes.first.maxX;
    double maxY = nodes.first.maxY;
    for (int i = 1; i < nodes.length; i++) {
      final _Node node = nodes[i];
      if (node.minX < minX) minX = node.minX;
      if (node.minY < minY) minY = node.minY;
      if (node.maxX > maxX) maxX = node.maxX;
      if (node.maxY > maxY) maxY = node.maxY;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static int _compareHitByCenterX(ElementHit a, ElementHit b) {
    final double ax = (a.bbox.left + a.bbox.right) * 0.5;
    final double bx = (b.bbox.left + b.bbox.right) * 0.5;
    final int cmp = ax.compareTo(bx);
    if (cmp != 0) {
      return cmp;
    }
    final double ay = (a.bbox.top + a.bbox.bottom) * 0.5;
    final double by = (b.bbox.top + b.bbox.bottom) * 0.5;
    return ay.compareTo(by);
  }

  static int _compareHitByCenterY(ElementHit a, ElementHit b) {
    final double ay = (a.bbox.top + a.bbox.bottom) * 0.5;
    final double by = (b.bbox.top + b.bbox.bottom) * 0.5;
    final int cmp = ay.compareTo(by);
    if (cmp != 0) {
      return cmp;
    }
    final double ax = (a.bbox.left + a.bbox.right) * 0.5;
    final double bx = (b.bbox.left + b.bbox.right) * 0.5;
    return ax.compareTo(bx);
  }

  static int _compareNodeByCenterX(_Node a, _Node b) {
    final int cmp = a.centerX.compareTo(b.centerX);
    if (cmp != 0) {
      return cmp;
    }
    return a.centerY.compareTo(b.centerY);
  }

  static int _compareNodeByCenterY(_Node a, _Node b) {
    final int cmp = a.centerY.compareTo(b.centerY);
    if (cmp != 0) {
      return cmp;
    }
    return a.centerX.compareTo(b.centerX);
  }
}

/// branch-and-bound NN 搜索的可变状态，避免逐层传参。
class _NNState {
  _NNState(this.px, this.py, this.types);
  final double px;
  final double py;
  final Set<String>? types;
  ElementHit? best;
  double bestDist = double.infinity;
}

/// 递归 NN 搜索，带 AABB 下界剪枝。
void _searchNearest(_Node node, _NNState s) {
  // 若当前节点 AABB 到查询点的最短距离已 >= 当前最优，整棵子树可剪掉
  final double nodeDist = _minDistToAABB(
    s.px, s.py, node.minX, node.minY, node.maxX, node.maxY,
  );
  if (nodeDist >= s.bestDist) return;

  final List<ElementHit>? hits = node.hits;
  if (hits != null) {
    // 叶子：逐元素检测
    for (final ElementHit hit in hits) {
      if (s.types != null && !s.types!.contains(hit.type)) continue;
      final double d = _minDistToAABB(
        s.px, s.py,
        hit.bbox.left, hit.bbox.top, hit.bbox.right, hit.bbox.bottom,
      );
      if (d < s.bestDist) {
        s.bestDist = d;
        s.best = hit;
      }
    }
    return;
  }

  // 内部节点：先访问 AABB 离查询点最近的子节点，
  // 更快更新 bestDist，从而更积极地剪掉远侧子树。
  final List<_Node> children = node.children!;
  final int len = children.length;

  // 计算每个子节点的 minDist，用插入排序按升序排列索引，避免额外 List 分配
  // maxChildren = 16，插入排序在此规模下比 sort() 快且无 GC 压力
  final List<int> order = List<int>.generate(len, (int i) => i);
  final List<double> dists = List<double>.filled(len, 0.0);
  for (int i = 0; i < len; i++) {
    final _Node c = children[i];
    dists[i] = _minDistToAABB(s.px, s.py, c.minX, c.minY, c.maxX, c.maxY);
  }
  // 插入排序：对 16 个元素，分支代价远低于调用 List.sort
  for (int i = 1; i < len; i++) {
    final int idx = order[i];
    final double d = dists[idx];
    int j = i - 1;
    while (j >= 0 && dists[order[j]] > d) {
      order[j + 1] = order[j];
      j--;
    }
    order[j + 1] = idx;
  }

  for (int i = 0; i < len; i++) {
    final _Node child = children[order[i]];
    // 剪枝：若该子节点的 minDist 已 >= bestDist，后面的更远，全部跳过
    if (dists[order[i]] >= s.bestDist) break;
    _searchNearest(child, s);
  }
}

/// 点 (px, py) 到 AABB [minX,minY,maxX,maxY] 的最短距离（点在内部时为 0）。
double _minDistToAABB(
  double px, double py,
  double minX, double minY, double maxX, double maxY,
) {
  final double dx = px < minX ? minX - px : (px > maxX ? px - maxX : 0.0);
  final double dy = py < minY ? minY - py : (py > maxY ? py - maxY : 0.0);
  return math.sqrt(dx * dx + dy * dy);
}

/// R-tree 节点。
class _Node {
  _Node.leaf(this.hits, this.minX, this.minY, this.maxX, this.maxY)
      : children = null;

  _Node.branch(this.children, this.minX, this.minY, this.maxX, this.maxY)
      : hits = null;

  /// 叶子节点命中的元素；内部节点为 `null`。
  final List<ElementHit>? hits;

  /// 内部节点的子节点；叶子节点为 `null`。
  final List<_Node>? children;

  /// 节点覆盖的 AABB。
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  bool get isLeaf => hits != null;

  double get centerX => (minX + maxX) * 0.5;
  double get centerY => (minY + maxY) * 0.5;
}
