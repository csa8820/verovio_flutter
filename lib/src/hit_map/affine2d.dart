import 'dart:math' as math;
import 'dart:typed_data';

/// 2x3 仿射矩阵，按行主序存储为：
///
/// ```text
/// [ a  b  tx ]
/// [ c  d  ty ]
/// ```
///
/// 仅使用一个 [Float64List] 保存，便于热路径复用。
class Affine2D {
  Affine2D.identity() : m = Float64List(6) {
    m[0] = 1.0;
    m[1] = 0.0;
    m[2] = 0.0;
    m[3] = 1.0;
    m[4] = 0.0;
    m[5] = 0.0;
  }

  Affine2D.translate(double tx, double ty) : m = Float64List(6) {
    m[0] = 1.0;
    m[1] = 0.0;
    m[2] = 0.0;
    m[3] = 1.0;
    m[4] = tx;
    m[5] = ty;
  }

  Affine2D.scale(double sx, double sy) : m = Float64List(6) {
    m[0] = sx;
    m[1] = 0.0;
    m[2] = 0.0;
    m[3] = sy;
    m[4] = 0.0;
    m[5] = 0.0;
  }

  /// 绕原点旋转 [radians]。
  Affine2D.rotate(double radians) : m = Float64List(6) {
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    m[0] = c;
    m[1] = -s;
    m[2] = s;
    m[3] = c;
    m[4] = 0.0;
    m[5] = 0.0;
  }

  Affine2D.matrix(
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
  ) : m = Float64List(6) {
    m[0] = a;
    m[1] = b;
    m[2] = c;
    m[3] = d;
    m[4] = tx;
    m[5] = ty;
  }

  /// 仿射矩阵存储：[a, b, c, d, tx, ty]。
  final Float64List m;

  /// in-place 右乘 [other]：`this = this * other`。
  ///
  /// 这是热路径方法，内部不分配新对象。
  void multiply(Affine2D other) {
    final double a0 = m[0];
    final double b0 = m[1];
    final double c0 = m[2];
    final double d0 = m[3];
    final double tx0 = m[4];
    final double ty0 = m[5];

    final Float64List o = other.m;
    final double a1 = o[0];
    final double b1 = o[1];
    final double c1 = o[2];
    final double d1 = o[3];
    final double tx1 = o[4];
    final double ty1 = o[5];

    m[0] = a0 * a1 + b0 * c1;
    m[1] = a0 * b1 + b0 * d1;
    m[2] = c0 * a1 + d0 * c1;
    m[3] = c0 * b1 + d0 * d1;
    m[4] = a0 * tx1 + b0 * ty1 + tx0;
    m[5] = c0 * tx1 + d0 * ty1 + ty0;
  }

  /// 将当前矩阵复制到 [dst]，不创建临时对象。
  void cloneInto(Affine2D dst) {
    final Float64List d = dst.m;
    d[0] = m[0];
    d[1] = m[1];
    d[2] = m[2];
    d[3] = m[3];
    d[4] = m[4];
    d[5] = m[5];
  }

  /// 应用到点 `(x, y)`，把结果写入 [outXY]，`outXY.length >= 2`。
  void transformPoint(double x, double y, Float64List outXY) {
    outXY[0] = m[0] * x + m[1] * y + m[4];
    outXY[1] = m[2] * x + m[3] * y + m[5];
  }

  /// 应用到 AABB，写入 [outRect]：`[minX, minY, maxX, maxY]`。
  ///
  /// 对带旋转/scale 的矩阵，取 4 个角点变换后的新外接矩形。
  void transformAabb(
    double minX,
    double minY,
    double maxX,
    double maxY,
    Float64List outRect,
  ) {
    final double a = m[0];
    final double b = m[1];
    final double c = m[2];
    final double d = m[3];
    final double tx = m[4];
    final double ty = m[5];

    double x = a * minX + b * minY + tx;
    double y = c * minX + d * minY + ty;
    double minOutX = x;
    double maxOutX = x;
    double minOutY = y;
    double maxOutY = y;

    x = a * maxX + b * minY + tx;
    y = c * maxX + d * minY + ty;
    if (x < minOutX) {
      minOutX = x;
    } else if (x > maxOutX) {
      maxOutX = x;
    }
    if (y < minOutY) {
      minOutY = y;
    } else if (y > maxOutY) {
      maxOutY = y;
    }

    x = a * minX + b * maxY + tx;
    y = c * minX + d * maxY + ty;
    if (x < minOutX) {
      minOutX = x;
    } else if (x > maxOutX) {
      maxOutX = x;
    }
    if (y < minOutY) {
      minOutY = y;
    } else if (y > maxOutY) {
      maxOutY = y;
    }

    x = a * maxX + b * maxY + tx;
    y = c * maxX + d * maxY + ty;
    if (x < minOutX) {
      minOutX = x;
    } else if (x > maxOutX) {
      maxOutX = x;
    }
    if (y < minOutY) {
      minOutY = y;
    } else if (y > maxOutY) {
      maxOutY = y;
    }

    outRect[0] = minOutX;
    outRect[1] = minOutY;
    outRect[2] = maxOutX;
    outRect[3] = maxOutY;
  }

  /// 仅平移快路径：等价于 `this.multiply(Affine2D.translate(tx, ty))`，
  /// 但直接更新平移项，避免分配对象。
  void translateOnly(double tx, double ty) {
    m[4] += m[0] * tx + m[1] * ty;
    m[5] += m[2] * tx + m[3] * ty;
  }

  /// 是否为单位矩阵。
  bool get isIdentity =>
      m[0] == 1.0 &&
      m[1] == 0.0 &&
      m[2] == 0.0 &&
      m[3] == 1.0 &&
      m[4] == 0.0 &&
      m[5] == 0.0;

  /// 是否仅包含平移项：`a=d=1, b=c=0`。
  bool get isTranslateOnly =>
      m[0] == 1.0 && m[1] == 0.0 && m[2] == 0.0 && m[3] == 1.0;
}
