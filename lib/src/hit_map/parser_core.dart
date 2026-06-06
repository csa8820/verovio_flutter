library verovio_flutter.hit_map.parser_core;

import 'package:verovio_flutter/src/hit_map/glyph_cache.dart';
import 'package:verovio_flutter/src/hit_map/models_data.dart';
import 'package:verovio_flutter/src/hit_map/path_bbox.dart';
import 'package:verovio_flutter/src/hit_map/shape_bbox.dart';
import 'package:verovio_flutter/src/hit_map/walker.dart';

/// HitMap 对外解析入口的纯 Dart 核心。
///
/// 这里不依赖 `dart:isolate` / `dart:ui`，因此可以被 Web Worker 直接复用。
class HitMapParserCore {
  static PageHitMapData parseSync(
    String svg, {
    int pageIndex = 0,
    ParseConfigData config = const ParseConfigData.defaultForInteractive(),
    GlyphBBoxCache? cache,
  }) {
    final GlyphBBoxCache glyphCache = cache ?? GlyphBBoxCache();
    final PathBBoxSolver pathSolver = PathBBoxSolver();
    final ShapeBBoxComputer shapeComp = ShapeBBoxComputer(
      glyphCache: glyphCache,
      pathSolver: pathSolver,
      pathMode: config.pathMode,
    );
    final HitMapWalker walker = HitMapWalker(
      config: config,
      glyphCache: glyphCache,
      pathSolver: pathSolver,
      shapeComp: shapeComp,
    );
    return walker.parseSync(svg, pageIndex);
  }
}
