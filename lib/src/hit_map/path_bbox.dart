import 'dart:typed_data';

import 'package:verovio_flutter/src/hit_map/geometry.dart';
import 'package:verovio_flutter/src/hit_map/models_data.dart';
import 'package:verovio_flutter/src/hit_map/path_bbox_core.dart';

/// SVG path `d` 属性边界框求解器。
///
/// 主循环复用 [Float64List]，避免重复分配。
class PathBBoxSolver {
  PathBBoxSolver() : _core = PathBBoxSolverCore();

  /// 复用的 buffer，避免重复 new。
  final Float64List _out = Float64List(4);

  final PathBBoxSolverCore _core;

  /// 解析 path 的 `d` 属性，把 bbox 写入 [outRect]（4 个 double）。
  ///
  /// [outRect] 复用以零分配。
  void solve(String d, HitMapPathBBoxMode mode, Float64List outRect) {
    _core.solve(d, mode == HitMapPathBBoxMode.accurate, outRect);
  }

  /// 便利方法：返回 [RectD]（内部仍走 solve）。
  RectD solveToRectD(String d, HitMapPathBBoxMode mode) {
    _core.solve(d, mode == HitMapPathBBoxMode.accurate, _out);
    return RectD.fromLTRB(_out[0], _out[1], _out[2], _out[3]);
  }
}
