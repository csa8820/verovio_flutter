import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

/// SVG path `d` 属性边界框求解核心。
///
/// 这是纯 Dart 版本，便于 benchmark 在 `dart` CLI 下直接运行。
class PathBBoxSolverCore {
  PathBBoxSolverCore();

  static const double _halfPi = math.pi / 2.0;
  static const double _twoPi = math.pi * 2.0;
  static const double _degToRad = math.pi / 180.0;
  static const double _eps = 1e-12;

  String _s = '';
  int _len = 0;
  int _i = 0;
  bool _accurate = true;
  late Float64List _outRect;

  int _cmd = 0;

  double _cx = 0.0;
  double _cy = 0.0;
  double _sx = 0.0;
  double _sy = 0.0;

  double _lastCubicCtrlX = 0.0;
  double _lastCubicCtrlY = 0.0;
  double _lastCubicCtrl1X = 0.0;
  double _lastCubicCtrl1Y = 0.0;
  double _lastQuadCtrlX = 0.0;
  double _lastQuadCtrlY = 0.0;
  bool _hasLastCubicCtrl = false;
  bool _hasLastQuadCtrl = false;

  double _minX = 0.0;
  double _minY = 0.0;
  double _maxX = 0.0;
  double _maxY = 0.0;
  bool _hasBBox = false;

  /// 解析 SVG path 的 `d` 属性到复用的 outRect。
  ///
  /// outRect 语义：[minX, minY, maxX, maxY]
  void solve(String d, bool accurate, Float64List outRect) {
    _s = d;
    _len = d.length;
    _i = 0;
    _accurate = accurate;
    _outRect = outRect;

    _cmd = 0;
    _cx = 0.0;
    _cy = 0.0;
    _sx = 0.0;
    _sy = 0.0;
    _lastCubicCtrlX = 0.0;
    _lastCubicCtrlY = 0.0;
    _lastCubicCtrl1X = 0.0;
    _lastCubicCtrl1Y = 0.0;
    _lastQuadCtrlX = 0.0;
    _lastQuadCtrlY = 0.0;
    _hasLastCubicCtrl = false;
    _hasLastQuadCtrl = false;
    _minX = 0.0;
    _minY = 0.0;
    _maxX = 0.0;
    _maxY = 0.0;
    _hasBBox = false;

    if (_len == 0) {
      _zeroOut();
      return;
    }

    while (_i < _len) {
      _skipDelimiters();
      if (_i >= _len) {
        break;
      }

      final int code = _s.codeUnitAt(_i);
      if (_isCommandChar(code)) {
        _cmd = code;
        _i++;
        if (code == 0x5A || code == 0x7A) {
          _closePath();
          _cmd = 0;
        }
        continue;
      }

      if (_cmd == 0) {
        developer.log(
          'SVG path 解析警告：未知字符 "$_currentChar"，已跳过。',
          name: 'path_bbox',
          level: 900,
        );
        _i++;
        continue;
      }

      final bool ok = _parseCurrentCommand();
      if (!ok) {
        developer.log(
          'SVG path 解析警告：命令 ${String.fromCharCode(_cmd)} 参数缺失或格式错误，已跳过。',
          name: 'path_bbox',
          level: 900,
        );
        _i++;
      }
    }

    if (!_hasBBox) {
      _zeroOut();
      return;
    }

    _outRect[0] = _minX;
    _outRect[1] = _minY;
    _outRect[2] = _maxX;
    _outRect[3] = _maxY;
  }

  void _zeroOut() {
    _outRect[0] = 0.0;
    _outRect[1] = 0.0;
    _outRect[2] = 0.0;
    _outRect[3] = 0.0;
  }

  bool _parseCurrentCommand() {
    switch (_cmd) {
      case 0x4D: // M
      case 0x6D: // m
        return _parseMove();
      case 0x4C: // L
      case 0x6C: // l
        return _parseLine();
      case 0x48: // H
      case 0x68: // h
        return _parseHorizontalLine();
      case 0x56: // V
      case 0x76: // v
        return _parseVerticalLine();
      case 0x43: // C
      case 0x63: // c
        return _parseCubic();
      case 0x53: // S
      case 0x73: // s
        return _parseSmoothCubic();
      case 0x51: // Q
      case 0x71: // q
        return _parseQuadratic();
      case 0x54: // T
      case 0x74: // t
        return _parseSmoothQuadratic();
      case 0x41: // A
      case 0x61: // a
        return _parseArc();
      default:
        return false;
    }
  }

  bool _parseMove() {
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }
    _skipDelimiters();
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x6D;
    final double nx = relative ? _cx + x : x;
    final double ny = relative ? _cy + y : y;

    _cx = nx;
    _cy = ny;
    _sx = nx;
    _sy = ny;
    _includePoint(nx, ny);
    _clearSmoothState();

    // SVG 规则：M/m 之后的同命令数字组等价于 L/l。
    _cmd = relative ? 0x6C : 0x4C;
    return true;
  }

  bool _parseLine() {
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }
    _skipDelimiters();
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x6C;
    final double nx = relative ? _cx + x : x;
    final double ny = relative ? _cy + y : y;
    _lineTo(nx, ny);
    return true;
  }

  bool _parseHorizontalLine() {
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }

    final bool relative = _cmd == 0x68;
    final double nx = relative ? _cx + x : x;
    _lineTo(nx, _cy);
    return true;
  }

  bool _parseVerticalLine() {
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x76;
    final double ny = relative ? _cy + y : y;
    _lineTo(_cx, ny);
    return true;
  }

  bool _parseCubic() {
    final double? x1 = _readNumber();
    if (x1 == null) {
      return false;
    }
    _skipDelimiters();
    final double? y1 = _readNumber();
    if (y1 == null) {
      return false;
    }
    _skipDelimiters();
    final double? x2 = _readNumber();
    if (x2 == null) {
      return false;
    }
    _skipDelimiters();
    final double? y2 = _readNumber();
    if (y2 == null) {
      return false;
    }
    _skipDelimiters();
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }
    _skipDelimiters();
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x63;
    final double c1x = relative ? _cx + x1 : x1;
    final double c1y = relative ? _cy + y1 : y1;
    final double c2x = relative ? _cx + x2 : x2;
    final double c2y = relative ? _cy + y2 : y2;
    final double ex = relative ? _cx + x : x;
    final double ey = relative ? _cy + y : y;

    _cubicTo(c1x, c1y, c2x, c2y, ex, ey);
    return true;
  }

  bool _parseSmoothCubic() {
    final double? x2 = _readNumber();
    if (x2 == null) {
      return false;
    }
    _skipDelimiters();
    final double? y2 = _readNumber();
    if (y2 == null) {
      return false;
    }
    _skipDelimiters();
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }
    _skipDelimiters();
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x73;
    final double c1x = _hasLastCubicCtrl ? _cx * 2.0 - _lastCubicCtrlX : _cx;
    final double c1y = _hasLastCubicCtrl ? _cy * 2.0 - _lastCubicCtrlY : _cy;
    final double c2x = relative ? _cx + x2 : x2;
    final double c2y = relative ? _cy + y2 : y2;
    final double ex = relative ? _cx + x : x;
    final double ey = relative ? _cy + y : y;

    if (_accurate) {
      if (_hasLastCubicCtrl) {
        _includePoint(_lastCubicCtrl1X, _lastCubicCtrl1Y);
        _includePoint(_lastCubicCtrlX, _lastCubicCtrlY);
      }
      _includePoint(c1x, c1y);
      _includePoint(c2x, c2y);
      _includePoint(ex, ey);
      _cx = ex;
      _cy = ey;
      _lastCubicCtrlX = c2x;
      _lastCubicCtrlY = c2y;
      _hasLastCubicCtrl = true;
      _hasLastQuadCtrl = false;
      return true;
    }
    _cubicTo(c1x, c1y, c2x, c2y, ex, ey);
    return true;
  }

  bool _parseQuadratic() {
    final double? x1 = _readNumber();
    if (x1 == null) {
      return false;
    }
    _skipDelimiters();
    final double? y1 = _readNumber();
    if (y1 == null) {
      return false;
    }
    _skipDelimiters();
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }
    _skipDelimiters();
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x71;
    final double cx1 = relative ? _cx + x1 : x1;
    final double cy1 = relative ? _cy + y1 : y1;
    final double ex = relative ? _cx + x : x;
    final double ey = relative ? _cy + y : y;

    _quadraticTo(cx1, cy1, ex, ey);
    return true;
  }

  bool _parseSmoothQuadratic() {
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }
    _skipDelimiters();
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x74;
    final double cx1 = _hasLastQuadCtrl ? _cx * 2.0 - _lastQuadCtrlX : _cx;
    final double cy1 = _hasLastQuadCtrl ? _cy * 2.0 - _lastQuadCtrlY : _cy;
    final double ex = relative ? _cx + x : x;
    final double ey = relative ? _cy + y : y;

    if (_accurate) {
      if (_hasLastQuadCtrl) {
        _includePoint(_lastQuadCtrlX, _lastQuadCtrlY);
      }
      _includePoint(cx1, cy1);
      _includePoint(ex, ey);
      _cx = ex;
      _cy = ey;
      _lastQuadCtrlX = cx1;
      _lastQuadCtrlY = cy1;
      _hasLastQuadCtrl = true;
      _hasLastCubicCtrl = false;
      return true;
    }
    _quadraticTo(cx1, cy1, ex, ey);
    return true;
  }

  bool _parseArc() {
    final double? rx = _readNumber();
    if (rx == null) {
      return false;
    }
    _skipDelimiters();
    final double? ry = _readNumber();
    if (ry == null) {
      return false;
    }
    _skipDelimiters();
    final double? xAxisRotation = _readNumber();
    if (xAxisRotation == null) {
      return false;
    }
    _skipDelimiters();
    final double? largeArcFlag = _readNumber();
    if (largeArcFlag == null) {
      return false;
    }
    _skipDelimiters();
    final double? sweepFlag = _readNumber();
    if (sweepFlag == null) {
      return false;
    }
    _skipDelimiters();
    final double? x = _readNumber();
    if (x == null) {
      return false;
    }
    _skipDelimiters();
    final double? y = _readNumber();
    if (y == null) {
      return false;
    }

    final bool relative = _cmd == 0x61;
    final double ex = relative ? _cx + x : x;
    final double ey = relative ? _cy + y : y;
    _arcTo(
      rx.abs(),
      ry.abs(),
      xAxisRotation,
      largeArcFlag != 0.0,
      sweepFlag != 0.0,
      ex,
      ey,
    );
    return true;
  }

  void _lineTo(double x, double y) {
    _includePoint(_cx, _cy);
    _includePoint(x, y);
    _cx = x;
    _cy = y;
    _clearSmoothState();
  }

  void _cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x,
    double y,
  ) {
    if (_accurate) {
      _includeCubicAccurate(_cx, _cy, x1, y1, x2, y2, x, y);
    } else {
      _includePoint(_cx, _cy);
      _includePoint(x1, y1);
      _includePoint(x2, y2);
      _includePoint(x, y);
    }

    _cx = x;
    _cy = y;
    _lastCubicCtrl1X = x1;
    _lastCubicCtrl1Y = y1;
    _lastCubicCtrlX = x2;
    _lastCubicCtrlY = y2;
    _hasLastCubicCtrl = true;
    _hasLastQuadCtrl = false;
  }

  void _quadraticTo(double x1, double y1, double x, double y) {
    if (_accurate) {
      _includeQuadraticAccurate(_cx, _cy, x1, y1, x, y);
    } else {
      _includePoint(_cx, _cy);
      _includePoint(x1, y1);
      _includePoint(x, y);
    }

    _cx = x;
    _cy = y;
    _lastQuadCtrlX = x1;
    _lastQuadCtrlY = y1;
    _hasLastQuadCtrl = true;
    _hasLastCubicCtrl = false;
  }

  void _closePath() {
    _cx = _sx;
    _cy = _sy;
    _clearSmoothState();
  }

  void _clearSmoothState() {
    _hasLastCubicCtrl = false;
    _hasLastQuadCtrl = false;
  }

  void _arcTo(
    double rx,
    double ry,
    double xAxisRotationDeg,
    bool largeArc,
    bool sweep,
    double x,
    double y,
  ) {
    final double x0 = _cx;
    final double y0 = _cy;
    if (rx == 0.0 || ry == 0.0 || (x0 == x && y0 == y)) {
      _lineTo(x, y);
      return;
    }

    final double phi = xAxisRotationDeg * _degToRad;
    final double cosPhi = math.cos(phi);
    final double sinPhi = math.sin(phi);

    final double dx2 = (x0 - x) / 2.0;
    final double dy2 = (y0 - y) / 2.0;
    double x1p = cosPhi * dx2 + sinPhi * dy2;
    double y1p = -sinPhi * dx2 + cosPhi * dy2;

    double rxSq = rx * rx;
    double rySq = ry * ry;
    final double x1pSq = x1p * x1p;
    final double y1pSq = y1p * y1p;

    double lambda = x1pSq / rxSq + y1pSq / rySq;
    if (lambda > 1.0) {
      final double scale = math.sqrt(lambda);
      rx *= scale;
      ry *= scale;
      rxSq = rx * rx;
      rySq = ry * ry;
    }

    final double sign = (largeArc == sweep) ? -1.0 : 1.0;
    final double numerator =
        (rxSq * rySq) - (rxSq * y1pSq) - (rySq * x1pSq);
    final double denominator = (rxSq * y1pSq) + (rySq * x1pSq);
    double coef = 0.0;
    if (denominator > _eps) {
      final double root = numerator / denominator;
      coef = sign * math.sqrt(root < 0.0 ? 0.0 : root);
    }

    final double cxp = coef * (rx * y1p / ry);
    final double cyp = coef * (-ry * x1p / rx);
    final double cx = cosPhi * cxp - sinPhi * cyp + (x0 + x) / 2.0;
    final double cy = sinPhi * cxp + cosPhi * cyp + (y0 + y) / 2.0;

    final double ux = (x1p - cxp) / rx;
    final double uy = (y1p - cyp) / ry;
    final double vx = (-x1p - cxp) / rx;
    final double vy = (-y1p - cyp) / ry;

    final double theta1 = _vectorAngle(1.0, 0.0, ux, uy);
    double deltaTheta = _vectorAngle(ux, uy, vx, vy);
    // SVG 的 sweepFlag 方向在 viewBox 的 y 轴向下坐标系里与常规数学
    // 坐标的直觉相反：sweep=1 需要优先走“下方”那条弧。
    if (sweep && deltaTheta > 0.0) {
      deltaTheta -= _twoPi;
    } else if (!sweep && deltaTheta < 0.0) {
      deltaTheta += _twoPi;
    }

    int segments = (deltaTheta.abs() / _halfPi).ceil();
    if (segments < 1) {
      segments = 1;
    } else if (segments > 4) {
      segments = 4;
    }
    final double delta = deltaTheta / segments;

    for (int i = 0; i < segments; i++) {
      final double th1 = theta1 + (delta * i);
      final double th2 = th1 + delta;
      final double sin1 = math.sin(th1);
      final double cos1 = math.cos(th1);
      final double sin2 = math.sin(th2);
      final double cos2 = math.cos(th2);
      final double alpha = (4.0 / 3.0) * math.tan((th2 - th1) / 4.0);

      final double p0x = _cx;
      final double p0y = _cy;
      final double p3x = _ellipsePointX(cx, cy, cosPhi, sinPhi, rx, ry, cos2, sin2);
      final double p3y = _ellipsePointY(cx, cy, cosPhi, sinPhi, rx, ry, cos2, sin2);
      final double dx1 = -cosPhi * rx * sin1 - sinPhi * ry * cos1;
      final double dy1 = -sinPhi * rx * sin1 + cosPhi * ry * cos1;
      final double dx2 = -cosPhi * rx * sin2 - sinPhi * ry * cos2;
      final double dy2 = -sinPhi * rx * sin2 + cosPhi * ry * cos2;

      final double c1x = p0x + alpha * dx1;
      final double c1y = p0y + alpha * dy1;
      final double c2x = p3x - alpha * dx2;
      final double c2y = p3y - alpha * dy2;

      _cubicTo(c1x, c1y, c2x, c2y, p3x, p3y);
    }
  }

  @pragma('vm:prefer-inline')
  void _includePoint(double x, double y) {
    if (!_hasBBox) {
      _minX = x;
      _maxX = x;
      _minY = y;
      _maxY = y;
      _hasBBox = true;
      return;
    }
    if (x < _minX) {
      _minX = x;
    } else if (x > _maxX) {
      _maxX = x;
    }
    if (y < _minY) {
      _minY = y;
    } else if (y > _maxY) {
      _maxY = y;
    }
  }

  void _includeQuadraticAccurate(
    double p0x,
    double p0y,
    double p1x,
    double p1y,
    double p2x,
    double p2y,
  ) {
    _includePoint(p0x, p0y);
    _includePoint(p2x, p2y);

    _includeQuadraticAxis(p0x, p1x, p2x, true);
    _includeQuadraticAxis(p0y, p1y, p2y, false);
  }

  void _includeQuadraticAxis(
    double p0,
    double p1,
    double p2,
    bool isX,
  ) {
    final double denom = p0 - (2.0 * p1) + p2;
    if (denom.abs() <= _eps) {
      return;
    }
    final double t = (p0 - p1) / denom;
    if (t <= 0.0 || t >= 1.0) {
      return;
    }
    final double value = _evalQuadratic(p0, p1, p2, t);
    if (isX) {
      _updateX(value);
    } else {
      _updateY(value);
    }
  }

  void _includeCubicAccurate(
    double p0x,
    double p0y,
    double p1x,
    double p1y,
    double p2x,
    double p2y,
    double p3x,
    double p3y,
  ) {
    _includePoint(p0x, p0y);
    _includePoint(p3x, p3y);
    _includeCubicAxis(p0x, p1x, p2x, p3x, true);
    _includeCubicAxis(p0y, p1y, p2y, p3y, false);
  }

  void _includeCubicAxis(
    double p0,
    double p1,
    double p2,
    double p3,
    bool isX,
  ) {
    final double a = -p0 + (3.0 * p1) - (3.0 * p2) + p3;
    final double b = 2.0 * (p0 - (2.0 * p1) + p2);
    final double c = p1 - p0;

    if (a.abs() <= _eps) {
      if (b.abs() > _eps) {
        final double t = -c / b;
        if (t > 0.0 && t < 1.0) {
      final double value = _evalCubic(p0, p1, p2, p3, t);
      if (isX) {
        _updateX(value);
      } else {
        _updateY(value);
      }
    }
      }
      return;
    }

    final double disc = (b * b) - (4.0 * a * c);
    if (disc < 0.0) {
      return;
    }

    final double sqrtDisc = math.sqrt(disc);
    final double inv2a = 1.0 / (2.0 * a);
    final double t1 = (-b - sqrtDisc) * inv2a;
    final double t2 = (-b + sqrtDisc) * inv2a;
    if (t1 > 0.0 && t1 < 1.0) {
      final double value = _evalCubic(p0, p1, p2, p3, t1);
      if (isX) {
        _updateX(value);
      } else {
        _updateY(value);
      }
    }
    if (t2 > 0.0 && t2 < 1.0) {
      final double value = _evalCubic(p0, p1, p2, p3, t2);
      if (isX) {
        _updateX(value);
      } else {
        _updateY(value);
      }
    }
  }

  @pragma('vm:prefer-inline')
  void _updateX(double x) {
    if (x < _minX) {
      _minX = x;
    } else if (x > _maxX) {
      _maxX = x;
    }
  }

  @pragma('vm:prefer-inline')
  void _updateY(double y) {
    if (y < _minY) {
      _minY = y;
    } else if (y > _maxY) {
      _maxY = y;
    }
  }

  @pragma('vm:prefer-inline')
  double _evalQuadratic(double p0, double p1, double p2, double t) {
    final double ab = p0 + ((p1 - p0) * t);
    final double bc = p1 + ((p2 - p1) * t);
    return ab + ((bc - ab) * t);
  }

  @pragma('vm:prefer-inline')
  double _evalCubic(
    double p0,
    double p1,
    double p2,
    double p3,
    double t,
  ) {
    final double ab = p0 + ((p1 - p0) * t);
    final double bc = p1 + ((p2 - p1) * t);
    final double cd = p2 + ((p3 - p2) * t);
    final double abc = ab + ((bc - ab) * t);
    final double bcd = bc + ((cd - bc) * t);
    return abc + ((bcd - abc) * t);
  }

  @pragma('vm:prefer-inline')
  double _vectorAngle(double ux, double uy, double vx, double vy) {
    return math.atan2((ux * vy) - (uy * vx), (ux * vx) + (uy * vy));
  }

  @pragma('vm:prefer-inline')
  double _ellipsePointX(
    double cx,
    double cy,
    double cosPhi,
    double sinPhi,
    double rx,
    double ry,
    double cosT,
    double sinT,
  ) {
    return cx + (cosPhi * rx * cosT) - (sinPhi * ry * sinT);
  }

  @pragma('vm:prefer-inline')
  double _ellipsePointY(
    double cx,
    double cy,
    double cosPhi,
    double sinPhi,
    double rx,
    double ry,
    double cosT,
    double sinT,
  ) {
    return cy + (sinPhi * rx * cosT) + (cosPhi * ry * sinT);
  }

  @pragma('vm:prefer-inline')
  void _skipDelimiters() {
    while (_i < _len) {
      final int code = _s.codeUnitAt(_i);
      if (code == 0x20 ||
          code == 0x09 ||
          code == 0x0A ||
          code == 0x0D ||
          code == 0x0C ||
          code == 0x2C) {
        _i++;
        continue;
      }
      break;
    }
  }

  @pragma('vm:prefer-inline')
  bool _isCommandChar(int code) {
    switch (code) {
      case 0x4D: // M
      case 0x6D: // m
      case 0x4C: // L
      case 0x6C: // l
      case 0x48: // H
      case 0x68: // h
      case 0x56: // V
      case 0x76: // v
      case 0x43: // C
      case 0x63: // c
      case 0x53: // S
      case 0x73: // s
      case 0x51: // Q
      case 0x71: // q
      case 0x54: // T
      case 0x74: // t
      case 0x41: // A
      case 0x61: // a
      case 0x5A: // Z
      case 0x7A: // z
        return true;
      default:
        return false;
    }
  }

  @pragma('vm:prefer-inline')
  String get _currentChar {
    if (_i < 0 || _i >= _len) {
      return '';
    }
    return _s[_i];
  }

  @pragma('vm:prefer-inline')
  double? _readNumber() {
    if (_i >= _len) {
      return null;
    }

    final int start = _i;
    int j = _i;

    if (j < _len) {
      final int sign = _s.codeUnitAt(j);
      if (sign == 0x2B || sign == 0x2D) {
        j++;
      }
    }

    bool hasDigits = false;
    double intPart = 0.0;
    while (j < _len) {
      final int code = _s.codeUnitAt(j);
      if (code < 0x30 || code > 0x39) {
        break;
      }
      intPart = (intPart * 10.0) + (code - 0x30).toDouble();
      j++;
      hasDigits = true;
    }

    double fracPart = 0.0;
    double fracScale = 1.0;
    if (j < _len && _s.codeUnitAt(j) == 0x2E) {
      j++;
      while (j < _len) {
        final int code = _s.codeUnitAt(j);
        if (code < 0x30 || code > 0x39) {
          break;
        }
        fracPart = (fracPart * 10.0) + (code - 0x30).toDouble();
        fracScale *= 10.0;
        j++;
        hasDigits = true;
      }
    }

    if (!hasDigits) {
      return null;
    }

    int exp = 0;
    bool expNegative = false;
    if (j < _len) {
      final int code = _s.codeUnitAt(j);
      if (code == 0x65 || code == 0x45) {
        int k = j + 1;
        if (k < _len) {
          final int expSign = _s.codeUnitAt(k);
          if (expSign == 0x2B || expSign == 0x2D) {
            expNegative = expSign == 0x2D;
            k++;
          }
        }
        final int expStart = k;
        while (k < _len) {
          final int expCode = _s.codeUnitAt(k);
          if (expCode < 0x30 || expCode > 0x39) {
            break;
          }
          exp = (exp * 10) + (expCode - 0x30);
          k++;
        }
        if (k > expStart) {
          j = k;
        }
      }
    }

    _i = j;
    double value = intPart + (fracPart / fracScale);
    if (start < _len && _s.codeUnitAt(start) == 0x2D) {
      value = -value;
    } else if (start < _len && _s.codeUnitAt(start) == 0x2B) {
      // keep positive
    }

    if (exp != 0) {
      final int signedExp = expNegative ? -exp : exp;
      value *= math.pow(10.0, signedExp).toDouble();
    }
    return value;
  }
}
