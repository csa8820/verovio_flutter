library verovio_flutter.hit_map.models_data;

import 'package:collection/collection.dart';

import 'package:verovio_flutter/src/hit_map/geometry.dart';

/// 路径 bbox 的计算模式。
enum HitMapPathBBoxMode {
  fast,
  accurate,
}

/// 纯 Dart 版本的单个元素命中信息。
class ElementHitData {
  const ElementHitData({
    required this.id,
    required this.type,
    required this.bbox,
    this.parentId,
    this.extra,
  });

  final String id;
  final String type;
  final RectD bbox;
  final String? parentId;
  final Map<String, String>? extra;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'bbox': bbox.toJson(),
        'parentId': parentId,
        'extra': extra,
      };

  factory ElementHitData.fromJson(Map<String, Object?> json) {
    final bboxJson = (json['bbox'] as Map).cast<String, Object?>();
    final extraJson = json['extra'];
    return ElementHitData(
      id: json['id'] as String,
      type: json['type'] as String,
      bbox: RectD.fromJson(bboxJson),
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
  bool operator ==(Object other) =>
      other is ElementHitData &&
      id == other.id &&
      type == other.type &&
      bbox == other.bbox &&
      parentId == other.parentId &&
      _mapEquality.equals(extra, other.extra);

  @override
  int get hashCode => Object.hash(
        id,
        type,
        bbox,
        parentId,
        extra == null ? null : _mapEquality.hash(extra!),
      );
}

/// 纯 Dart 版本的整页 HitMap。
class PageHitMapData {
  PageHitMapData({
    required this.pageIndex,
    required this.viewBox,
    required Map<String, ElementHitData> byId,
    required List<ElementHitData> byType,
    required this.parseTime,
  })  : byId = UnmodifiableMapView<String, ElementHitData>(
          Map<String, ElementHitData>.from(byId),
        ),
        byType = UnmodifiableListView<ElementHitData>(
          List<ElementHitData>.from(byType),
        );

  final int pageIndex;
  final SizeD viewBox;
  final UnmodifiableMapView<String, ElementHitData> byId;
  final UnmodifiableListView<ElementHitData> byType;
  final Duration parseTime;

  Map<String, Object?> toJson() => <String, Object?>{
        'pageIndex': pageIndex,
        'viewBox': viewBox.toJson(),
        'byId': byId.map(
          (String key, ElementHitData value) => MapEntry<String, Object?>(
            key,
            value.toJson(),
          ),
        ),
        'byType': byType.map((ElementHitData value) => value.toJson()).toList(),
        'parseTimeMicros': parseTime.inMicroseconds,
      };

  factory PageHitMapData.fromJson(Map<String, Object?> json) {
    final byIdJson = (json['byId'] as Map).cast<String, Object?>();
    final byTypeJson = (json['byType'] as List).cast<Object?>();
    return PageHitMapData(
      pageIndex: (json['pageIndex'] as num).toInt(),
      viewBox: SizeD.fromJson((json['viewBox'] as Map).cast<String, Object?>()),
      byId: byIdJson.map((k, v) => MapEntry(
            k,
            ElementHitData.fromJson((v as Map).cast<String, Object?>()),
          )),
      byType: byTypeJson
          .map((v) => ElementHitData.fromJson((v as Map).cast<String, Object?>()))
          .toList(),
      parseTime: Duration(
        microseconds: (json['parseTimeMicros'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  static const MapEquality<String, ElementHitData> _mapEquality =
      MapEquality<String, ElementHitData>();
  static const ListEquality<ElementHitData> _listEquality =
      ListEquality<ElementHitData>();

  @override
  bool operator ==(Object other) =>
      other is PageHitMapData &&
      pageIndex == other.pageIndex &&
      viewBox == other.viewBox &&
      _mapEquality.equals(byId, other.byId) &&
      _listEquality.equals(byType, other.byType) &&
      parseTime == other.parseTime;

  @override
  int get hashCode => Object.hash(
        pageIndex,
        viewBox,
        _mapEquality.hash(byId),
        _listEquality.hash(byType),
        parseTime,
      );
}

/// 纯 Dart 版本的解析配置。
class ParseConfigData {
  const ParseConfigData({
    this.captureClasses,
    this.buildSpatialIndex = true,
    this.extraAttrs = const <String>{},
    this.pathMode = HitMapPathBBoxMode.accurate,
    this.skipDecorative = false,
  });

  const factory ParseConfigData.defaultForInteractive() =
      ParseConfigData._defaultForInteractive;

  const factory ParseConfigData.measureOnly() = ParseConfigData._measureOnly;

  const factory ParseConfigData.full() = ParseConfigData._full;

  const ParseConfigData._defaultForInteractive()
      : captureClasses = const <String>{'note', 'rest', 'measure'},
        buildSpatialIndex = true,
        extraAttrs = const <String>{},
        pathMode = HitMapPathBBoxMode.accurate,
        skipDecorative = false;

  const ParseConfigData._measureOnly()
      : captureClasses = const <String>{'measure'},
        buildSpatialIndex = false,
        extraAttrs = const <String>{},
        pathMode = HitMapPathBBoxMode.accurate,
        skipDecorative = false;

  const ParseConfigData._full()
      : captureClasses = null,
        buildSpatialIndex = true,
        extraAttrs = const <String>{},
        pathMode = HitMapPathBBoxMode.accurate,
        skipDecorative = false;

  final Set<String>? captureClasses;
  final bool buildSpatialIndex;
  final Set<String> extraAttrs;
  final HitMapPathBBoxMode pathMode;
  final bool skipDecorative;

  Map<String, Object?> toJson() => <String, Object?>{
        'captureClasses': captureClasses?.toList(growable: false),
        'buildSpatialIndex': buildSpatialIndex,
        'extraAttrs': extraAttrs.toList(growable: false),
        'pathMode': pathMode.name,
        'skipDecorative': skipDecorative,
      };

  factory ParseConfigData.fromJson(Map<String, Object?> json) {
    final captureClassesJson = json['captureClasses'];
    final extraAttrsJson = json['extraAttrs'];
    return ParseConfigData(
      captureClasses: captureClassesJson == null
          ? null
          : (captureClassesJson as List)
              .cast<Object?>()
              .map((v) => v as String)
              .toSet(),
      buildSpatialIndex: json['buildSpatialIndex'] as bool? ?? true,
      extraAttrs: extraAttrsJson == null
          ? const <String>{}
          : (extraAttrsJson as List)
              .cast<Object?>()
              .map((v) => v as String)
              .toSet(),
      pathMode: HitMapPathBBoxMode.values.byName(
        json['pathMode'] as String? ?? HitMapPathBBoxMode.accurate.name,
      ),
      skipDecorative: json['skipDecorative'] as bool? ?? false,
    );
  }

  static const SetEquality<String> _setEquality = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is ParseConfigData &&
      _setEquals(captureClasses, other.captureClasses) &&
      buildSpatialIndex == other.buildSpatialIndex &&
      _setEquality.equals(extraAttrs, other.extraAttrs) &&
      pathMode == other.pathMode &&
      skipDecorative == other.skipDecorative;

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
