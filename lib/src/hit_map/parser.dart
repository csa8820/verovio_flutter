import 'dart:isolate';

import 'package:verovio_flutter/src/hit_map/glyph_cache.dart';
import 'package:verovio_flutter/src/hit_map/models.dart';
import 'package:verovio_flutter/src/hit_map/path_bbox.dart';
import 'package:verovio_flutter/src/hit_map/shape_bbox.dart';
import 'package:verovio_flutter/src/hit_map/walker.dart';

/// HitMap 对外解析入口。
class HitMapParser {
  /// 同步版本，给 isolate worker 内部直接调用；
  /// 也可用于已知在 background isolate 中的场景。
  static PageHitMap parseSync(
    String svg, {
    int pageIndex = 0,
    ParseConfig config = const ParseConfig.defaultForInteractive(),
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

  /// 异步版本：主 isolate 调用时自动 Isolate.run；
  /// 已在 background isolate 时调用方应直接用 parseSync 避免嵌套 isolate。
  static Future<PageHitMap> parse(
    String svg, {
    int pageIndex = 0,
    ParseConfig config = const ParseConfig.defaultForInteractive(),
  }) {
    return Isolate.run(
      () => parseSync(
        svg,
        pageIndex: pageIndex,
        config: config,
      ),
    );
  }
}
