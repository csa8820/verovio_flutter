import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:verovio_flutter/src/hit_map/affine2d.dart';

/// 解析 SVG transform 属性，并将结果合入 [dst]：
/// `dst = dst * parsedTransform`。
void applyTransformInto(String? transformStr, Affine2D dst) {
  if (transformStr == null) {
    return;
  }
  if (transformStr.trim().isEmpty) {
    return;
  }
  _TransformParser(transformStr, dst).parse();
}

class _TransformParser {
  _TransformParser(this._s, this._dst);

  final String _s;
  final Affine2D _dst;
  int _i = 0;

  int get len => _s.length;

  void parse() {
    while (true) {
      _skipSeparators();
      if (_i >= len) {
        return;
      }

      final int nameStart = _i;
      while (_i < len) {
        final int code = _s.codeUnitAt(_i);
        if (_isNameChar(code)) {
          _i++;
          continue;
        }
        break;
      }
      if (_i == nameStart) {
        developer.log(
          'SVG transform 解析失败：无法识别函数名，已跳过剩余片段。',
          name: 'transform_parser',
          level: 900,
        );
        return;
      }

      final String name = _s.substring(nameStart, _i);
      _skipSeparators();
      if (_i >= len || _s.codeUnitAt(_i) != 0x28) {
        developer.log(
          'SVG transform 解析失败：函数 $name 缺少 "("，已跳过。',
          name: 'transform_parser',
          level: 900,
        );
        _skipUntilNextTransform();
        continue;
      }
      _i++; // consume '('

      switch (name) {
        case 'translate':
          _parseTranslate();
          break;
        case 'scale':
          _parseScale();
          break;
        case 'rotate':
          _parseRotate();
          break;
        case 'matrix':
          _parseMatrix();
          break;
        case 'skewX':
          _parseSkewX();
          break;
        case 'skewY':
          _parseSkewY();
          break;
        default:
          developer.log(
            '未知 SVG transform 函数：$name，已跳过。',
            name: 'transform_parser',
            level: 900,
          );
          _skipParenGroup();
          break;
      }
    }
  }

  void _parseTranslate() {
    final double? tx = _readNumber();
    if (tx == null) {
      _warnMalformed('translate');
      return;
    }
    _skipSeparators();
    double ty = 0.0;
    final double? maybeTy = _readNumber();
    if (maybeTy != null) {
      ty = maybeTy;
    }
    _skipSeparators();
    if (!_consumeCloseParen()) {
      _warnMalformed('translate');
      return;
    }
    _dst.translateOnly(tx, ty);
  }

  void _parseScale() {
    final double? sx = _readNumber();
    if (sx == null) {
      _warnMalformed('scale');
      return;
    }
    _skipSeparators();
    double sy = sx;
    final double? maybeSy = _readNumber();
    if (maybeSy != null) {
      sy = maybeSy;
    }
    _skipSeparators();
    if (!_consumeCloseParen()) {
      _warnMalformed('scale');
      return;
    }
    _multiplyScale(sx, sy);
  }

  void _parseRotate() {
    final double? angleDeg = _readNumber();
    if (angleDeg == null) {
      _warnMalformed('rotate');
      return;
    }
    _skipSeparators();
    final double angleRad = angleDeg * math.pi / 180.0;
    final double? cxOrNull = _readNumber();
    if (cxOrNull == null) {
      _skipSeparators();
      if (!_consumeCloseParen()) {
        _warnMalformed('rotate');
        return;
      }
      _multiplyRotate(angleRad);
      return;
    }

    _skipSeparators();
    final double? cy = _readNumber();
    if (cy == null) {
      _warnMalformed('rotate');
      return;
    }
    _skipSeparators();
    if (!_consumeCloseParen()) {
      _warnMalformed('rotate');
      return;
    }
    _multiplyTranslate(cxOrNull, cy);
    _multiplyRotate(angleRad);
    _multiplyTranslate(-cxOrNull, -cy);
  }

  void _parseMatrix() {
    final double? a = _readNumber();
    final double? b = _readNumberAfterSeparator();
    final double? c = _readNumberAfterSeparator();
    final double? d = _readNumberAfterSeparator();
    final double? e = _readNumberAfterSeparator();
    final double? f = _readNumberAfterSeparator();
    _skipSeparators();
    if (a == null ||
        b == null ||
        c == null ||
        d == null ||
        e == null ||
        f == null ||
        !_consumeCloseParen()) {
      _warnMalformed('matrix');
      return;
    }
    _multiplyMatrix(a, b, c, d, e, f);
  }

  void _parseSkewX() {
    final double? angleDeg = _readNumber();
    if (angleDeg == null) {
      _warnMalformed('skewX');
      return;
    }
    _skipSeparators();
    if (!_consumeCloseParen()) {
      _warnMalformed('skewX');
      return;
    }
    _multiplySkewX(angleDeg * math.pi / 180.0);
  }

  void _parseSkewY() {
    final double? angleDeg = _readNumber();
    if (angleDeg == null) {
      _warnMalformed('skewY');
      return;
    }
    _skipSeparators();
    if (!_consumeCloseParen()) {
      _warnMalformed('skewY');
      return;
    }
    _multiplySkewY(angleDeg * math.pi / 180.0);
  }

  void _warnMalformed(String name) {
    developer.log(
      'SVG transform $name(...) 参数不完整或格式错误，已跳过。',
      name: 'transform_parser',
      level: 900,
    );
    _skipParenGroup();
  }

  void _skipUntilNextTransform() {
    while (_i < len) {
      final int code = _s.codeUnitAt(_i);
      if (code == 0x29) {
        _i++;
        return;
      }
      _i++;
    }
  }

  void _skipParenGroup() {
    int depth = 1;
    while (_i < len) {
      final int code = _s.codeUnitAt(_i++);
      if (code == 0x28) {
        depth++;
      } else if (code == 0x29) {
        depth--;
        if (depth == 0) {
          return;
        }
      }
    }
  }

  void _skipSeparators() {
    while (_i < len) {
      final int code = _s.codeUnitAt(_i);
      if (code == 0x20 ||
          code == 0x09 ||
          code == 0x0a ||
          code == 0x0d ||
          code == 0x0c ||
          code == 0x2c) {
        _i++;
        continue;
      }
      break;
    }
  }

  bool _consumeCloseParen() {
    if (_i < len && _s.codeUnitAt(_i) == 0x29) {
      _i++;
      return true;
    }
    return false;
  }

  double? _readNumberAfterSeparator() {
    _skipSeparators();
    return _readNumber();
  }

  double? _readNumber() {
    if (_i >= len) {
      return null;
    }
    final int start = _i;
    int j = _i;

    if (_isSign(_s.codeUnitAt(j))) {
      j++;
      if (j >= len) {
        return null;
      }
    }

    int digits = 0;
    while (j < len && _isDigit(_s.codeUnitAt(j))) {
      j++;
      digits++;
    }

    if (j < len && _s.codeUnitAt(j) == 0x2e) {
      j++;
      while (j < len && _isDigit(_s.codeUnitAt(j))) {
        j++;
        digits++;
      }
    }

    if (digits == 0) {
      return null;
    }

    if (j < len && (_s.codeUnitAt(j) == 0x65 || _s.codeUnitAt(j) == 0x45)) {
      int k = j + 1;
      if (k < len && _isSign(_s.codeUnitAt(k))) {
        k++;
      }
      final int expStart = k;
      while (k < len && _isDigit(_s.codeUnitAt(k))) {
        k++;
      }
      if (k > expStart) {
        j = k;
      }
    }

    _i = j;
    return double.tryParse(_s.substring(start, j));
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isSign(int code) => code == 0x2b || code == 0x2d;

  static bool _isNameChar(int code) {
    return (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a) ||
        code == 0x58 ||
        code == 0x59;
  }

  void _multiplyTranslate(double tx, double ty) {
    final Float64List m = _dst.m;
    m[4] += m[0] * tx + m[1] * ty;
    m[5] += m[2] * tx + m[3] * ty;
  }

  void _multiplyScale(double sx, double sy) {
    final Float64List m = _dst.m;
    m[0] *= sx;
    m[1] *= sy;
    m[2] *= sx;
    m[3] *= sy;
  }

  void _multiplyRotate(double radians) {
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    final Float64List m = _dst.m;
    final double a0 = m[0];
    final double b0 = m[1];
    final double c0 = m[2];
    final double d0 = m[3];
    m[0] = a0 * c + b0 * s;
    m[1] = -a0 * s + b0 * c;
    m[2] = c0 * c + d0 * s;
    m[3] = -c0 * s + d0 * c;
  }

  void _multiplyMatrix(
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
  ) {
    final Float64List m = _dst.m;
    final double a0 = m[0];
    final double b0 = m[1];
    final double c0 = m[2];
    final double d0 = m[3];
    final double tx0 = m[4];
    final double ty0 = m[5];

    m[0] = a0 * a + b0 * c;
    m[1] = a0 * b + b0 * d;
    m[2] = c0 * a + d0 * c;
    m[3] = c0 * b + d0 * d;
    m[4] = a0 * tx + b0 * ty + tx0;
    m[5] = c0 * tx + d0 * ty + ty0;
  }

  void _multiplySkewX(double radians) {
    _multiplyMatrix(1.0, math.tan(radians), 0.0, 1.0, 0.0, 0.0);
  }

  void _multiplySkewY(double radians) {
    _multiplyMatrix(1.0, 0.0, math.tan(radians), 1.0, 0.0, 0.0);
  }
}
