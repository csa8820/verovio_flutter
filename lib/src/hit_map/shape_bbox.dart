import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui';

import 'package:verovio_flutter/src/hit_map/glyph_cache.dart';
import 'package:verovio_flutter/src/hit_map/models.dart';
import 'package:verovio_flutter/src/hit_map/path_bbox.dart';

/// 轻量属性访问接口，避免绑定具体 XML 库实现。
abstract class ShapeAttrs {
  /// 读取属性值；不存在时返回 null。
  String? operator [](String name);
}

/// 基于 Map 的属性实现，供单测和轻量调用方使用。
class MapShapeAttrs implements ShapeAttrs {
  const MapShapeAttrs(this.data);

  final Map<String, String> data;

  @override
  String? operator [](String name) => data[name];
}

/// 形状 bbox 适配器：把 leaf 元素转成局部坐标系下的 AABB。
///
/// 注意：这里**不处理 transform**，也不读取 class / id 等信息；
/// 这些都由 walker 在 frame 栈里统一完成。
class ShapeBBoxComputer {
  ShapeBBoxComputer({
    required this.glyphCache,
    required this.pathSolver,
    this.pathMode = PathBBoxMode.accurate,
  });

  final GlyphBBoxCache glyphCache;
  final PathBBoxSolver pathSolver;
  final PathBBoxMode pathMode;

  /// 写入 outRect [minX, minY, maxX, maxY]，失败时写入退化点。
  bool useBBox(ShapeAttrs a, Float64List outRect) {
    final String? href = a['xlink:href'] ?? a['href'];
    final double x = _readDouble(a, 'x');
    final double y = _readDouble(a, 'y');
    final double? width = _readOptionalDouble(a, 'width');
    final double? height = _readOptionalDouble(a, 'height');

    final Rect? symbolBBox = href == null ? null : glyphCache.lookup(href);
    if (symbolBBox == null) {
      _writePoint(outRect, x, y);
      _warn('Glyph not found: $href');
      return false;
    }

    if (width == null || height == null) {
      _writeRect(
        outRect,
        symbolBBox.left + x,
        symbolBBox.top + y,
        symbolBBox.right + x,
        symbolBBox.bottom + y,
      );
      return _isNonDegenerate(outRect);
    }

    // 目标宽高存在时，<use> 的外接矩形就是目标渲染框。
    // 当字形自身宽高为 0 时，避免除零，直接按目标框处理。
    if (symbolBBox.width == 0.0 || symbolBBox.height == 0.0) {
      _writeRect(outRect, x, y, x + width, y + height);
      return _isNonDegenerate(outRect);
    }

    final double scaleX = width / symbolBBox.width;
    final double scaleY = height / symbolBBox.height;
    _writeRect(outRect, x, y, x + symbolBBox.width * scaleX,
        y + symbolBBox.height * scaleY);
    return _isNonDegenerate(outRect);
  }

  /// rect 的局部 bbox。
  bool rectBBox(ShapeAttrs a, Float64List outRect) {
    final double x = _readDouble(a, 'x');
    final double y = _readDouble(a, 'y');
    final double width = _readDouble(a, 'width');
    final double height = _readDouble(a, 'height');
    final double x2 = x + width;
    final double y2 = y + height;
    _writeRect(
      outRect,
      x < x2 ? x : x2,
      y < y2 ? y : y2,
      x > x2 ? x : x2,
      y > y2 ? y : y2,
    );
    return _isNonDegenerate(outRect);
  }

  /// line 的局部 bbox。
  bool lineBBox(ShapeAttrs a, Float64List outRect) {
    final double x1 = _readDouble(a, 'x1');
    final double y1 = _readDouble(a, 'y1');
    final double x2 = _readDouble(a, 'x2');
    final double y2 = _readDouble(a, 'y2');
    _writeRect(
      outRect,
      x1 < x2 ? x1 : x2,
      y1 < y2 ? y1 : y2,
      x1 > x2 ? x1 : x2,
      y1 > y2 ? y1 : y2,
    );
    return _isNonDegenerate(outRect);
  }

  /// polygon 的局部 bbox。
  bool polygonBBox(ShapeAttrs a, Float64List outRect) {
    return _pointsBBox(a['points'], outRect, 'polygon');
  }

  /// polyline 的局部 bbox。
  bool polylineBBox(ShapeAttrs a, Float64List outRect) {
    return _pointsBBox(a['points'], outRect, 'polyline');
  }

  /// ellipse 的局部 bbox。
  bool ellipseBBox(ShapeAttrs a, Float64List outRect) {
    final double cx = _readDouble(a, 'cx');
    final double cy = _readDouble(a, 'cy');
    final double rx = _readDouble(a, 'rx');
    final double ry = _readDouble(a, 'ry');
    _writeRect(outRect, cx - rx, cy - ry, cx + rx, cy + ry);
    return _isNonDegenerate(outRect);
  }

  /// circle 的局部 bbox。
  bool circleBBox(ShapeAttrs a, Float64List outRect) {
    final double cx = _readDouble(a, 'cx');
    final double cy = _readDouble(a, 'cy');
    final double r = _readDouble(a, 'r');
    _writeRect(outRect, cx - r, cy - r, cx + r, cy + r);
    return _isNonDegenerate(outRect);
  }

  /// path 的局部 bbox。
  bool pathBBox(ShapeAttrs a, Float64List outRect) {
    final String? d = a['d'];
    if (d == null || d.trim().isEmpty) {
      _writeZero(outRect);
      return false;
    }
    pathSolver.solve(d, pathMode, outRect);
    return _isNonDegenerate(outRect);
  }

  bool _pointsBBox(String? points, Float64List outRect, String shapeName) {
    if (points == null || points.trim().isEmpty) {
      _writeZero(outRect);
      return false;
    }

    final _PointsParser parser = _PointsParser(points);
    double? minX;
    double? minY;
    double? maxX;
    double? maxY;

    bool haveX = false;
    double x = 0.0;
    bool sawAnyPair = false;

    while (true) {
      final String? token = parser.nextToken();
      if (token == null) {
        break;
      }

      final double value = double.tryParse(token.trim()) ?? 0.0;
      if (!haveX) {
        x = value;
        haveX = true;
        continue;
      }

      final double y = value;
      if (!sawAnyPair) {
        minX = x;
        maxX = x;
        minY = y;
        maxY = y;
        sawAnyPair = true;
      } else {
        final double currentMinX = minX!;
        final double currentMaxX = maxX!;
        final double currentMinY = minY!;
        final double currentMaxY = maxY!;
        if (x < currentMinX) minX = x;
        if (x > currentMaxX) maxX = x;
        if (y < currentMinY) minY = y;
        if (y > currentMaxY) maxY = y;
      }
      haveX = false;
    }

    if (haveX) {
      _warn('$shapeName points 个数为奇数，已截去最后一个孤立值。');
    }

    if (!sawAnyPair ||
        minX == null ||
        minY == null ||
        maxX == null ||
        maxY == null) {
      _writeZero(outRect);
      return false;
    }

    _writeRect(outRect, minX, minY, maxX, maxY);
    return _isNonDegenerate(outRect);
  }

  static double _readDouble(ShapeAttrs a, String name) {
    return _readOptionalDouble(a, name) ?? 0.0;
  }

  static double? _readOptionalDouble(ShapeAttrs a, String name) {
    final String? raw = a[name];
    if (raw == null) {
      return null;
    }
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 0.0;
    }
    return double.tryParse(trimmed) ?? 0.0;
  }

  static void _writeZero(Float64List outRect) {
    outRect[0] = 0.0;
    outRect[1] = 0.0;
    outRect[2] = 0.0;
    outRect[3] = 0.0;
  }

  static void _writePoint(Float64List outRect, double x, double y) {
    outRect[0] = x;
    outRect[1] = y;
    outRect[2] = x;
    outRect[3] = y;
  }

  static void _writeRect(
    Float64List outRect,
    double minX,
    double minY,
    double maxX,
    double maxY,
  ) {
    outRect[0] = minX;
    outRect[1] = minY;
    outRect[2] = maxX;
    outRect[3] = maxY;
  }

  static bool _isNonDegenerate(Float64List outRect) {
    return outRect[2] > outRect[0] && outRect[3] > outRect[1];
  }

  static void _warn(String message) {
    developer.log(
      message,
      name: 'shape_bbox',
      level: 900,
    );
  }
}

/// points 属性的轻量解析器：只按空白 / 逗号分隔，不用正则。
class _PointsParser {
  _PointsParser(this._s);

  final String _s;
  int _i = 0;

  String? nextToken() {
    _skipSeparators();
    if (_i >= _s.length) {
      return null;
    }

    final int start = _i;
    while (_i < _s.length) {
      final int code = _s.codeUnitAt(_i);
      if (_isSeparator(code)) {
        break;
      }
      _i++;
    }
    return _s.substring(start, _i);
  }

  void _skipSeparators() {
    while (_i < _s.length) {
      final int code = _s.codeUnitAt(_i);
      if (_isSeparator(code)) {
        _i++;
        continue;
      }
      break;
    }
  }

  static bool _isSeparator(int code) {
    return code == 0x20 || // space
        code == 0x09 || // tab
        code == 0x0a || // lf
        code == 0x0d || // cr
        code == 0x0c || // ff
        code == 0x2c; // comma
  }
}
