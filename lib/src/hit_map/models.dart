import 'dart:ui';

import 'package:collection/collection.dart';

import 'package:verovio_flutter/src/hit_map/spatial_index.dart';

/// 单页 HitMap：保存一页 SVG 的全部命中数据。
class PageHitMap {
  PageHitMap({
    required this.pageIndex,
    required this.viewBox,
    required Map<String, ElementHit> byId,
    required List<ElementHit> byType,
    this.rTree,
    required this.parseTime,
  })  : byId = UnmodifiableMapView<String, ElementHit>(
          Map<String, ElementHit>.from(byId),
        ),
        byType = UnmodifiableListView<ElementHit>(
          List<ElementHit>.from(byType),
        );

  /// 页码索引。
  final int pageIndex;

  /// SVG 原始 viewBox 尺寸。
  final Size viewBox;

  /// id → 元素命中信息。
  final UnmodifiableMapView<String, ElementHit> byId;

  /// 按类型扁平化后的命中列表。
  final UnmodifiableListView<ElementHit> byType;

  /// 空间索引：仅用于查询加速，不参与序列化。
  final SpatialIndex? rTree;

  /// 解析耗时。
  final Duration parseTime;

  /// 转成 JSON 结构，便于跨 isolate 序列化。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageIndex': pageIndex,
      'viewBox': <String, Object?>{
        'width': viewBox.width,
        'height': viewBox.height,
      },
      'byId': byId.map(
        (String key, ElementHit value) => MapEntry<String, Object?>(
          key,
          value.toJson(),
        ),
      ),
      'byType': byType.map((ElementHit value) => value.toJson()).toList(),
      'parseTimeMicros': parseTime.inMicroseconds,
    };
  }

  /// 从 JSON 结构恢复对象。
  factory PageHitMap.fromJson(Map<String, Object?> json) {
    final byIdJson = (json['byId'] as Map).cast<String, Object?>();
    final byTypeJson = (json['byType'] as List).cast<Object?>();
    return PageHitMap(
      pageIndex: (json['pageIndex'] as num).toInt(),
      viewBox: Size(
        ((json['viewBox'] as Map)['width'] as num).toDouble(),
        ((json['viewBox'] as Map)['height'] as num).toDouble(),
      ),
      byId: byIdJson.map(
        (String key, Object? value) => MapEntry<String, ElementHit>(
          key,
          ElementHit.fromJson((value as Map).cast<String, Object?>()),
        ),
      ),
      byType: byTypeJson
          .map((Object? value) =>
              ElementHit.fromJson((value as Map).cast<String, Object?>()))
          .toList(),
      parseTime: Duration(
        microseconds: (json['parseTimeMicros'] as num?)?.toInt() ?? 0,
      ),
      rTree: null,
    );
  }

  static const MapEquality<String, ElementHit> _mapEquality =
      MapEquality<String, ElementHit>();
  static const ListEquality<ElementHit> _listEquality =
      ListEquality<ElementHit>();

  @override
  bool operator ==(Object other) {
    return other is PageHitMap &&
        pageIndex == other.pageIndex &&
        viewBox == other.viewBox &&
        _mapEquality.equals(byId, other.byId) &&
        _listEquality.equals(byType, other.byType) &&
        parseTime == other.parseTime;
  }

  @override
  int get hashCode => Object.hash(
        pageIndex,
        viewBox,
        _mapEquality.hash(byId),
        _listEquality.hash(byType),
        parseTime,
      );
}

/// 单个元素的命中信息。
class ElementHit {
  const ElementHit({
    required this.id,
    required this.type,
    required this.bbox,
    this.parentId,
    this.extra,
  });

  /// 元素 id。
  final String id;

  /// 元素类型，也就是 class/type。
  final String type;

  /// 在 viewBox 坐标系中的边界框。
  final Rect bbox;

  /// 最近的带 id 的祖先。
  final String? parentId;

  /// 额外属性，供后续扩展。
  final Map<String, String>? extra;

  /// 转成 JSON 结构。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'bbox': <String, Object?>{
        'left': bbox.left,
        'top': bbox.top,
        'width': bbox.width,
        'height': bbox.height,
      },
      'parentId': parentId,
      'extra': extra,
    };
  }

  /// 从 JSON 结构恢复对象。
  factory ElementHit.fromJson(Map<String, Object?> json) {
    final bboxJson = (json['bbox'] as Map).cast<String, Object?>();
    final extraJson = json['extra'];
    return ElementHit(
      id: json['id'] as String,
      type: json['type'] as String,
      bbox: Rect.fromLTWH(
        (bboxJson['left'] as num).toDouble(),
        (bboxJson['top'] as num).toDouble(),
        (bboxJson['width'] as num).toDouble(),
        (bboxJson['height'] as num).toDouble(),
      ),
      parentId: json['parentId'] as String?,
      extra: extraJson == null
          ? null
          : (extraJson as Map).map(
              (Object? key, Object? value) => MapEntry<String, String>(
                key as String,
                value as String,
              ),
            ),
    );
  }

  static const MapEquality<String, String> _mapEquality =
      MapEquality<String, String>();

  @override
  bool operator ==(Object other) {
    return other is ElementHit &&
        id == other.id &&
        type == other.type &&
        bbox == other.bbox &&
        parentId == other.parentId &&
        _mapEquality.equals(extra, other.extra);
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        bbox,
        parentId,
        extra == null ? null : _mapEquality.hash(extra!),
      );
}

/// 解析配置。
class ParseConfig {
  const ParseConfig({
    this.captureClasses,
    this.buildSpatialIndex = true,
    this.extraAttrs = const <String>{},
    this.pathMode = PathBBoxMode.accurate,
    this.skipDecorative = false,
  });

  /// 交互默认预设：只抓常用命中类，并开启空间索引。
  const factory ParseConfig.defaultForInteractive() =
      ParseConfig._defaultForInteractive;

  /// 只抓 measure，且不开空间索引。
  const factory ParseConfig.measureOnly() = ParseConfig._measureOnly;

  /// 全量抓取。
  const factory ParseConfig.full() = ParseConfig._full;

  const ParseConfig._defaultForInteractive()
      : captureClasses = const <String>{'note', 'rest', 'measure'},
        buildSpatialIndex = true,
        extraAttrs = const <String>{},
        pathMode = PathBBoxMode.accurate,
        skipDecorative = false;

  const ParseConfig._measureOnly()
      : captureClasses = const <String>{'measure'},
        buildSpatialIndex = false,
        extraAttrs = const <String>{},
        pathMode = PathBBoxMode.accurate,
        skipDecorative = false;

  const ParseConfig._full()
      : captureClasses = null,
        buildSpatialIndex = true,
        extraAttrs = const <String>{},
        pathMode = PathBBoxMode.accurate,
        skipDecorative = false;

  /// 要采集的 class 集合，null 表示全部。
  final Set<String>? captureClasses;

  /// 是否构建空间索引。
  final bool buildSpatialIndex;

  /// 额外要保留的属性名。
  final Set<String> extraAttrs;

  /// path bbox 计算模式。
  final PathBBoxMode pathMode;

  /// 是否跳过装饰性节点。
  final bool skipDecorative;

  /// 用作页面缓存 key 的稳定 hash。
  int get configHash => Object.hash(
        captureClasses == null
            ? -1
            : const SetEquality<String>().hash(captureClasses!),
        buildSpatialIndex,
        const SetEquality<String>().hash(extraAttrs),
        pathMode,
        skipDecorative,
      );

  /// 转成 JSON 结构。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'captureClasses': captureClasses?.toList(growable: false),
      'buildSpatialIndex': buildSpatialIndex,
      'extraAttrs': extraAttrs.toList(growable: false),
      'pathMode': pathMode.name,
      'skipDecorative': skipDecorative,
    };
  }

  /// 从 JSON 结构恢复对象。
  factory ParseConfig.fromJson(Map<String, Object?> json) {
    final captureClassesJson = json['captureClasses'];
    final extraAttrsJson = json['extraAttrs'];
    return ParseConfig(
      captureClasses: captureClassesJson == null
          ? null
          : (captureClassesJson as List)
              .cast<Object?>()
              .map((Object? value) => value as String)
              .toSet(),
      buildSpatialIndex: json['buildSpatialIndex'] as bool? ?? true,
      extraAttrs: extraAttrsJson == null
          ? const <String>{}
          : (extraAttrsJson as List)
              .cast<Object?>()
              .map((Object? value) => value as String)
              .toSet(),
      pathMode: PathBBoxMode.values.byName(
        json['pathMode'] as String? ?? PathBBoxMode.accurate.name,
      ),
      skipDecorative: json['skipDecorative'] as bool? ?? false,
    );
  }

  static const SetEquality<String> _setEquality = SetEquality<String>();

  @override
  bool operator ==(Object other) {
    return other is ParseConfig &&
        _setEquals(captureClasses, other.captureClasses) &&
        buildSpatialIndex == other.buildSpatialIndex &&
        _setEquality.equals(extraAttrs, other.extraAttrs) &&
        pathMode == other.pathMode &&
        skipDecorative == other.skipDecorative;
  }

  @override
  int get hashCode => Object.hash(
        captureClasses == null ? -1 : _setEquality.hash(captureClasses!),
        buildSpatialIndex,
        _setEquality.hash(extraAttrs),
        pathMode,
        skipDecorative,
      );

  static bool _setEquals(Set<String>? a, Set<String>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return _setEquality.equals(a, b);
  }
}

/// 路径 bbox 的计算模式。
enum PathBBoxMode {
  fast,
  accurate,
}
