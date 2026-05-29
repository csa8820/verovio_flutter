import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui';

import 'package:xml/xml_events.dart';

import 'package:verovio_flutter/src/hit_map/affine2d.dart';
import 'package:verovio_flutter/src/hit_map/glyph_cache.dart';
import 'package:verovio_flutter/src/hit_map/models.dart';
import 'package:verovio_flutter/src/hit_map/spatial_index.dart';
import 'package:verovio_flutter/src/hit_map/path_bbox.dart';
import 'package:verovio_flutter/src/hit_map/shape_bbox.dart';
import 'package:verovio_flutter/src/hit_map/transform_parser.dart';

/// SVG → HitMap 的流式 walker。
///
/// 维护帧栈、解析 defs/glyph、累积 leaf bbox，最终生成 PageHitMap。
class HitMapWalker {
  HitMapWalker({
    required this.config,
    required this.glyphCache,
    required this.pathSolver,
    required this.shapeComp,
    this.onLeafBBoxComputed,
  })  : _captureClasses = config.captureClasses ??
            (config.skipDecorative
                ? const <String>{'note', 'rest', 'measure'}
                : null),
        _extraAttrNames = config.extraAttrs.toList(growable: false),
        _extraAttrCount = config.extraAttrs.length,
        _leafAttrs = _MutableShapeAttrs() {
    // 预分配 32 帧，覆盖绝大多数 verovio SVG 深度。
    for (var i = 0; i < 32; i++) {
      _framePool.add(_Frame(_extraAttrCount));
    }
  }

  final ParseConfig config;
  final GlyphBBoxCache glyphCache;
  final PathBBoxSolver pathSolver;
  final ShapeBBoxComputer shapeComp;

  /// 测试 / 诊断钩子：每次真正进入 leaf bbox 计算时触发。
  final void Function(LeafKind kind)? onLeafBBoxComputed;

  /// 当前帧栈。
  final List<_Frame> _stack = <_Frame>[];

  /// 帧对象池（freelist）。
  final List<_Frame> _framePool = <_Frame>[];

  /// id → hit，保持插入顺序。
  final Map<String, ElementHit> _byId = <String, ElementHit>{};

  /// 扁平类型索引。
  final List<ElementHit> _byType = <ElementHit>[];

  /// 是否位于 `<defs>` 内。
  bool _inDefs = false;

  /// 当前 `<symbol>` 的临时状态。
  String? _currentSymbolId;
  String? _currentSymbolViewBox;
  String? _currentSymbolPathD;

  /// 复用 buffer：叶子 bbox 与变换后 bbox。
  final Float64List _leafBuf = Float64List(4);
  final Float64List _transformedBuf = Float64List(4);
  final Affine2D _leafTransform = Affine2D.identity();

  /// 顶层 SVG 的 viewBox 尺寸。
  Size? _viewBox;

  /// 解析计时。
  late Stopwatch _sw;

  /// 过滤集合缓存。
  final Set<String>? _captureClasses;

  /// 额外属性名缓存。
  final List<String> _extraAttrNames;

  final int _extraAttrCount;

  /// 复用的属性视图，避免叶子节点创建临时对象。
  final _MutableShapeAttrs _leafAttrs;

  /// 主入口：同步解析 SVG 文本，返回整页 HitMap。
  PageHitMap parseSync(String svgText, int pageIndex) {
    _resetState();
    _sw = Stopwatch()..start();

    final Iterable<XmlEvent> events = XmlEventDecoder().convert(svgText);
    for (final XmlEvent event in events) {
      if (event is XmlStartElementEvent) {
        _handleStart(event);
        if (event.isSelfClosing) {
          _handleEnd(event.localName);
        }
      } else if (event is XmlEndElementEvent) {
        _handleEnd(event.localName);
      }
    }

    SpatialIndex? rTree;
    if (config.buildSpatialIndex && _byType.isNotEmpty) {
      rTree = SpatialIndex.build(_byType);
    }

    _sw.stop();
    return PageHitMap(
      pageIndex: pageIndex,
      viewBox: _viewBox ?? Size.zero,
      byId: UnmodifiableMapView<String, ElementHit>(_byId),
      byType: UnmodifiableListView<ElementHit>(_byType),
      rTree: rTree,
      parseTime: _sw.elapsed,
    );
  }

  void _resetState() {
    _stack.clear();
    _byId.clear();
    _byType.clear();
    _inDefs = false;
    _currentSymbolId = null;
    _currentSymbolViewBox = null;
    _currentSymbolPathD = null;
    _viewBox = null;
  }

  void _handleStart(XmlStartElementEvent event) {
    if (_inDefs) {
      switch (event.localName) {
        case 'symbol':
        case 'g':
          _enterSymbol(event);
          return;
        case 'path':
          if (_currentSymbolId != null) {
            _currentSymbolPathD = _attrValue(event.attributes, 'd');
          }
          return;
        case 'defs':
          return;
        default:
          return;
      }
    }

    switch (event.localName) {
      case 'svg':
        _handleSvg(event);
        break;
      case 'defs':
        _inDefs = true;
        break;
      case 'g':
        _pushFrameFromElement(event, event.localName);
        break;
      case 'use':
        _handleLeaf(event, LeafKind.use);
        break;
      case 'rect':
        _handleLeaf(event, LeafKind.rect);
        break;
      case 'line':
        _handleLeaf(event, LeafKind.line);
        break;
      case 'path':
        _handleLeaf(event, LeafKind.path);
        break;
      case 'polygon':
        _handleLeaf(event, LeafKind.polygon);
        break;
      case 'polyline':
        _handleLeaf(event, LeafKind.polyline);
        break;
      case 'ellipse':
        _handleLeaf(event, LeafKind.ellipse);
        break;
      case 'circle':
        _handleLeaf(event, LeafKind.circle);
        break;
      case 'text':
        _handleText(event);
        break;
      default:
        break;
    }
  }

  void _handleEnd(String localName) {
    if (_inDefs) {
      switch (localName) {
        case 'symbol':
        case 'g':
          _finishSymbol();
          return;
        case 'defs':
          _inDefs = false;
          return;
        default:
          return;
      }
    }

    switch (localName) {
      case 'g':
      case 'svg':
        _popFrame();
        return;
      default:
        return;
    }
  }

  void _handleSvg(XmlStartElementEvent event) {
    final bool isRoot = _stack.isEmpty;
    final bool isDefinitionScale =
        _hasClass(event.attributes, 'definition-scale');

    if (!isRoot && !isDefinitionScale) {
      // 只按设计处理顶层 <svg> 与 definition-scale 嵌套 <svg>。
      return;
    }

    if (isRoot) {
      _viewBox =
          _parseSizeFromViewBox(_attrValue(event.attributes, 'viewBox')) ??
              _parseSizeFromWidthHeight(event.attributes) ??
              Size.zero;
    }

    _pushFrameFromElement(event, event.localName, isSvg: true);

    if (!isDefinitionScale) {
      return;
    }

    // 额外叠加 definition-scale 的 viewBox 缩放。
    final Size outer = _viewBox ?? Size.zero;
    final Size? inner =
        _parseSizeFromViewBox(_attrValue(event.attributes, 'viewBox'));
    if (inner != null && inner.width > 0.0 && inner.height > 0.0) {
      final double sx = outer.width > 0.0 ? outer.width / inner.width : 1.0;
      final double sy = outer.height > 0.0 ? outer.height / inner.height : 1.0;
      _stack.last.absTransform.multiply(Affine2D.scale(sx, sy));
    }
  }

  void _enterSymbol(XmlStartElementEvent event) {
    _currentSymbolId = _attrValue(event.attributes, 'id');
    _currentSymbolViewBox = _attrValue(event.attributes, 'viewBox');
    _currentSymbolPathD = null;
  }

  void _finishSymbol() {
    final String? id = _currentSymbolId;
    if (id != null) {
      populateGlyphFromSymbol(
        id: id,
        symbolViewBox: _currentSymbolViewBox,
        pathD: _currentSymbolPathD,
        solver: pathSolver,
        mode: config.pathMode,
        cache: glyphCache,
      );
    }
    _currentSymbolId = null;
    _currentSymbolViewBox = null;
    _currentSymbolPathD = null;
  }

  void _pushFrameFromElement(
    XmlStartElementEvent event,
    String localName, {
    bool isSvg = false,
  }) {
    final _Frame frame = _acquireFrame();
    final _Frame? parent = _stack.isEmpty ? null : _stack.last;
    if (parent != null) {
      parent.absTransform.cloneInto(frame.absTransform);
    }

    final String? rawClass = _attrValue(event.attributes, 'class');
    final String? type = _frameType(localName, rawClass);
    frame.id = _attrValue(event.attributes, 'id');
    frame.type = type;
    frame.shouldEmit = _shouldEmitFrame(frame.id, type);
    frame.ancestorOrSelfWantsBBox =
        (parent?.ancestorOrSelfWantsBBox ?? false) || frame.shouldEmit;

    if (_extraAttrCount > 0) {
      _captureExtraAttrs(event.attributes, frame);
    }

    final String? transform = _attrValue(event.attributes, 'transform');
    if (transform != null && transform.trim().isNotEmpty) {
      applyTransformInto(transform, frame.absTransform);
    }

    if (isSvg) {
      // 顶层 svg 仅作为普通帧使用；definition-scale 的额外缩放已在上层合并。
    }

    _stack.add(frame);
  }

  void _handleLeaf(XmlStartElementEvent event, LeafKind kind) {
    final _Frame? current = _stack.isEmpty ? null : _stack.last;
    if (current == null) {
      return;
    }

    // 早剪枝：栈上无人需要 bbox，就直接跳过这一 leaf。
    if (!current.ancestorOrSelfWantsBBox) {
      return;
    }

    final _MutableShapeAttrs attrs = _leafAttrs..attributes = event.attributes;
    _resetLeafTransform();
    final String? leafTransform = _attrValue(event.attributes, 'transform');
    if (leafTransform != null && leafTransform.trim().isNotEmpty) {
      applyTransformInto(leafTransform, _leafTransform);
    }
    onLeafBBoxComputed?.call(kind);
    bool ok;
    switch (kind) {
      case LeafKind.use:
        ok = shapeComp.useBBox(attrs, _leafBuf);
        break;
      case LeafKind.rect:
        ok = shapeComp.rectBBox(attrs, _leafBuf);
        break;
      case LeafKind.line:
        ok = shapeComp.lineBBox(attrs, _leafBuf);
        break;
      case LeafKind.path:
        ok = shapeComp.pathBBox(attrs, _leafBuf);
        break;
      case LeafKind.polygon:
        ok = shapeComp.polygonBBox(attrs, _leafBuf);
        break;
      case LeafKind.polyline:
        ok = shapeComp.polylineBBox(attrs, _leafBuf);
        break;
      case LeafKind.ellipse:
        ok = shapeComp.ellipseBBox(attrs, _leafBuf);
        break;
      case LeafKind.circle:
        ok = shapeComp.circleBBox(attrs, _leafBuf);
        break;
    }

    if (!ok) {
      return;
    }

    if (_leafTransform.isIdentity) {
      current.absTransform.transformAabb(
        _leafBuf[0],
        _leafBuf[1],
        _leafBuf[2],
        _leafBuf[3],
        _transformedBuf,
      );
    } else {
      _leafTransform.transformAabb(
        _leafBuf[0],
        _leafBuf[1],
        _leafBuf[2],
        _leafBuf[3],
        _transformedBuf,
      );
      current.absTransform.transformAabb(
        _transformedBuf[0],
        _transformedBuf[1],
        _transformedBuf[2],
        _transformedBuf[3],
        _transformedBuf,
      );
    }
    _mergeIntoCurrentFrame(_transformedBuf);
  }

  void _handleText(XmlStartElementEvent event) {
    final _Frame? current = _stack.isEmpty ? null : _stack.last;
    if (current == null || !current.ancestorOrSelfWantsBBox) {
      return;
    }

    _resetLeafTransform();
    final String? leafTransform = _attrValue(event.attributes, 'transform');
    if (leafTransform != null && leafTransform.trim().isNotEmpty) {
      applyTransformInto(leafTransform, _leafTransform);
    }

    final double x = _parseDouble(_attrValue(event.attributes, 'x'));
    final double y = _parseDouble(_attrValue(event.attributes, 'y'));
    final double rawFontSize =
        _parseDouble(_attrValue(event.attributes, 'font-size'));
    final double fontSize = rawFontSize > 0.0 ? rawFontSize : 16.0;
    final double estimatedWidth =
        _parseDouble(_attrValue(event.attributes, 'textLength'));
    final double width = estimatedWidth > 0.0 ? estimatedWidth : fontSize;

    _leafBuf[0] = x;
    _leafBuf[1] = y;
    _leafBuf[2] = x + width;
    _leafBuf[3] = y + fontSize;

    if (_leafTransform.isIdentity) {
      current.absTransform.transformAabb(
        _leafBuf[0],
        _leafBuf[1],
        _leafBuf[2],
        _leafBuf[3],
        _transformedBuf,
      );
    } else {
      _leafTransform.transformAabb(
        _leafBuf[0],
        _leafBuf[1],
        _leafBuf[2],
        _leafBuf[3],
        _transformedBuf,
      );
      current.absTransform.transformAabb(
        _transformedBuf[0],
        _transformedBuf[1],
        _transformedBuf[2],
        _transformedBuf[3],
        _transformedBuf,
      );
    }
    _mergeIntoCurrentFrame(_transformedBuf);
  }

  void _resetLeafTransform() {
    _leafTransform.m[0] = 1.0;
    _leafTransform.m[1] = 0.0;
    _leafTransform.m[2] = 0.0;
    _leafTransform.m[3] = 1.0;
    _leafTransform.m[4] = 0.0;
    _leafTransform.m[5] = 0.0;
  }

  void _mergeIntoCurrentFrame(Float64List bbox) {
    final _Frame current = _stack.last;
    final double minX = bbox[0];
    final double minY = bbox[1];
    final double maxX = bbox[2];
    final double maxY = bbox[3];

    if (!current.bboxValid) {
      current.minX = minX;
      current.minY = minY;
      current.maxX = maxX;
      current.maxY = maxY;
      current.bboxValid = true;
      return;
    }

    if (minX < current.minX) current.minX = minX;
    if (minY < current.minY) current.minY = minY;
    if (maxX > current.maxX) current.maxX = maxX;
    if (maxY > current.maxY) current.maxY = maxY;
  }

  void _popFrame() {
    if (_stack.isEmpty) {
      return;
    }

    final _Frame frame = _stack.removeLast();
    final String? parentId = _findNearestAncestorId();
    if (frame.shouldEmit &&
        frame.bboxValid &&
        frame.id != null &&
        frame.type != null) {
      final ElementHit hit = ElementHit(
        id: frame.id!,
        type: frame.type!,
        bbox: Rect.fromLTRB(frame.minX, frame.minY, frame.maxX, frame.maxY),
        parentId: parentId,
        extra: _buildExtraMap(frame),
      );
      _byId[hit.id] = hit;
      _byType.add(hit);
    }

    if (_stack.isNotEmpty && frame.bboxValid) {
      final _Frame parent = _stack.last;
      if (!parent.bboxValid) {
        parent.minX = frame.minX;
        parent.minY = frame.minY;
        parent.maxX = frame.maxX;
        parent.maxY = frame.maxY;
        parent.bboxValid = true;
      } else {
        if (frame.minX < parent.minX) parent.minX = frame.minX;
        if (frame.minY < parent.minY) parent.minY = frame.minY;
        if (frame.maxX > parent.maxX) parent.maxX = frame.maxX;
        if (frame.maxY > parent.maxY) parent.maxY = frame.maxY;
      }
    }

    frame.reset();
    _framePool.add(frame);
  }

  String? _findNearestAncestorId() {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final String? id = _stack[i].id;
      if (id != null) {
        return id;
      }
    }
    return null;
  }

  _Frame _acquireFrame() {
    if (_framePool.isNotEmpty) {
      final _Frame frame = _framePool.removeLast();
      frame.reset();
      return frame;
    }
    return _Frame(_extraAttrCount);
  }

  bool _shouldEmitFrame(String? id, String? type) {
    if (id == null || type == null) {
      return false;
    }
    final Set<String>? capture = _captureClasses;
    if (capture == null) {
      return true;
    }
    return capture.contains(type);
  }

  void _captureExtraAttrs(List<XmlEventAttribute> attrs, _Frame frame) {
    final List<String?> values = frame.extraValues!;
    for (var i = 0; i < _extraAttrCount; i++) {
      final String name = _extraAttrNames[i];
      values[i] = _attrValue(attrs, name);
    }
  }

  Map<String, String>? _buildExtraMap(_Frame frame) {
    if (_extraAttrCount == 0) {
      return null;
    }
    final List<String?> values = frame.extraValues!;
    bool any = false;
    for (final String? value in values) {
      if (value != null) {
        any = true;
        break;
      }
    }
    if (!any) {
      return null;
    }
    final Map<String, String> extra = <String, String>{};
    for (var i = 0; i < _extraAttrCount; i++) {
      final String? value = values[i];
      if (value != null) {
        extra[_extraAttrNames[i]] = value;
      }
    }
    return extra.isEmpty ? null : extra;
  }

  String? _frameType(String localName, String? rawClass) {
    if (rawClass == null || rawClass.trim().isEmpty) {
      return localName;
    }
    final String trimmed = rawClass.trim();
    final int space = trimmed.indexOf(' ');
    return space == -1 ? trimmed : trimmed.substring(0, space);
  }

  bool _hasClass(List<XmlEventAttribute> attrs, String wanted) {
    final String? rawClass = _attrValue(attrs, 'class');
    if (rawClass == null || rawClass.isEmpty) {
      return false;
    }
    if (rawClass == wanted) {
      return true;
    }
    int start = 0;
    while (start < rawClass.length) {
      while (start < rawClass.length && rawClass.codeUnitAt(start) == 0x20) {
        start++;
      }
      int end = start;
      while (end < rawClass.length && rawClass.codeUnitAt(end) != 0x20) {
        end++;
      }
      if (end > start && rawClass.substring(start, end) == wanted) {
        return true;
      }
      start = end + 1;
    }
    return false;
  }

  static String? _attrValue(List<XmlEventAttribute> attrs, String name) {
    for (final XmlEventAttribute attr in attrs) {
      if (attr.qualifiedName == name || attr.localName == name) {
        return attr.value;
      }
    }
    return null;
  }

  static double _parseDouble(String? raw) {
    if (raw == null) {
      return 0.0;
    }
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 0.0;
    }
    final double? direct = double.tryParse(trimmed);
    if (direct != null) {
      return direct;
    }
    int end = 0;
    while (end < trimmed.length) {
      final int code = trimmed.codeUnitAt(end);
      if ((code >= 0x30 && code <= 0x39) ||
          code == 0x2b ||
          code == 0x2d ||
          code == 0x2e ||
          code == 0x65 ||
          code == 0x45) {
        end++;
        continue;
      }
      break;
    }
    if (end == 0) {
      return 0.0;
    }
    return double.tryParse(trimmed.substring(0, end)) ?? 0.0;
  }

  static Size? _parseSizeFromViewBox(String? viewBox) {
    if (viewBox == null || viewBox.trim().isEmpty) {
      return null;
    }
    final List<String> parts = viewBox
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    if (parts.length != 4) {
      return null;
    }
    final double? w = double.tryParse(parts[2]);
    final double? h = double.tryParse(parts[3]);
    if (w == null || h == null) {
      return null;
    }
    return Size(w, h);
  }

  static Size? _parseSizeFromWidthHeight(List<XmlEventAttribute> attrs) {
    final double width = _parseDouble(_attrValue(attrs, 'width'));
    final double height = _parseDouble(_attrValue(attrs, 'height'));
    if (width <= 0.0 || height <= 0.0) {
      return null;
    }
    return Size(width, height);
  }
}

/// 叶子元素的种类。
enum LeafKind { use, rect, line, path, polygon, polyline, ellipse, circle }

/// 帧对象：可从 freelist 复用。
class _Frame {
  _Frame(int extraAttrCount)
      : absTransform = Affine2D.identity(),
        extraValues = extraAttrCount > 0
            ? List<String?>.filled(extraAttrCount, null)
            : null;

  final Affine2D absTransform;

  double minX = 0.0;
  double minY = 0.0;
  double maxX = 0.0;
  double maxY = 0.0;
  bool bboxValid = false;
  String? id;
  String? type;
  bool shouldEmit = false;
  bool ancestorOrSelfWantsBBox = false;
  final List<String?>? extraValues;

  void reset() {
    absTransform.m[0] = 1.0;
    absTransform.m[1] = 0.0;
    absTransform.m[2] = 0.0;
    absTransform.m[3] = 1.0;
    absTransform.m[4] = 0.0;
    absTransform.m[5] = 0.0;
    minX = 0.0;
    minY = 0.0;
    maxX = 0.0;
    maxY = 0.0;
    bboxValid = false;
    id = null;
    type = null;
    shouldEmit = false;
    ancestorOrSelfWantsBBox = false;
    final List<String?>? values = extraValues;
    if (values != null) {
      for (var i = 0; i < values.length; i++) {
        values[i] = null;
      }
    }
  }
}

/// 可复用的 ShapeAttrs 视图，避免叶子节点构造新对象。
class _MutableShapeAttrs implements ShapeAttrs {
  List<XmlEventAttribute>? attributes;

  @override
  String? operator [](String name) {
    final List<XmlEventAttribute>? attrs = attributes;
    if (attrs == null) {
      return null;
    }
    for (final XmlEventAttribute attr in attrs) {
      if (attr.qualifiedName == name || attr.localName == name) {
        return attr.value;
      }
    }
    return null;
  }
}
