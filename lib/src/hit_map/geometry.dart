/// Pure-Dart geometry value types for the hit_map parsing pipeline.
///
/// These mirror the small subset of `dart:ui` `Rect`/`Size` used internally by
/// the parser, but carry **zero** `dart:ui` / Flutter dependency so the same
/// parsing code can run inside a `dart compile js` Web Worker (no Flutter engine).
///
/// The public API (`ElementHit.bbox` as `dart:ui.Rect`) is unchanged; conversion
/// happens only at the io main-thread boundary. JSON shape is kept identical to
/// the existing serialization contract so `PageHitMap.fromJson` keeps working.
library;

/// Immutable axis-aligned rectangle (left/top/width/height), pure Dart.
class RectD {
  const RectD.fromLTWH(this.left, this.top, this.width, this.height);

  const RectD.fromLTRB(double left, double top, double right, double bottom)
      : left = left,
        top = top,
        width = right - left,
        height = bottom - top;

  /// The empty rectangle at the origin.
  static const RectD zero = RectD.fromLTWH(0, 0, 0, 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  /// True when this rect encloses no area.
  bool get isEmpty => width <= 0.0 || height <= 0.0;

  Map<String, Object?> toJson() => <String, Object?>{
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  static RectD fromJson(Map<String, Object?> json) => RectD.fromLTWH(
        (json['left'] as num).toDouble(),
        (json['top'] as num).toDouble(),
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is RectD &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'RectD.fromLTWH($left, $top, $width, $height)';
}

/// Immutable size (width/height), pure Dart.
class SizeD {
  const SizeD(this.width, this.height);

  /// The zero size.
  static const SizeD zero = SizeD(0, 0);

  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
        'width': width,
        'height': height,
      };

  static SizeD fromJson(Map<String, Object?> json) => SizeD(
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is SizeD && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'SizeD($width, $height)';
}
