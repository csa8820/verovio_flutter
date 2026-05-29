# HitMap 对外调用文档

> 状态：v1.0（与 verovio\_flutter 0.2.0+ 同步）
> 适用：所有使用 `verovio_flutter` 做乐谱交互的 Flutter App / 上层包

本文是 **API 参考 + 调用 cookbook**。

- 只想 5 分钟上手 → 看 [hit\_map.md](./hit_map.md)

***

## 1. 概念速览

```
[verovio C++] ── SVG 字符串 ──┐
                              │
                              ▼
                ┌─────────────────────────┐
                │  HitMap 解析（isolate）  │
                │   - 流式 SAX 遍历        │
                │   - SMuFL 字形 bbox 缓存 │
                │   - STR R-tree 空间索引  │
                └─────────────────────────┘
                              │
                              ▼
                       PageHitMap
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       hitTestPoint    hitTestRect    hitTestPointAll
              │               │               │
              ▼               ▼               ▼
                       ElementHit
                  { id, type, bbox, parentId, extra }
```

***

## 2. 公共 API 全集

只需要 `import 'package:verovio_flutter/verovio_flutter.dart';` 就能拿到下面所有符号。

### 2.1 数据类型

| 类型             | 用途                                                             |
| -------------- | -------------------------------------------------------------- |
| `PageHitMap`   | 单页解析结果，含 `byId` / `byType` / `viewBox` / `rTree` / `parseTime` |
| `ElementHit`   | 单个元素的命中信息（id / type / bbox / parentId / extra）                 |
| `ParseConfig`  | 解析配置（要采集哪些 class、是否建索引、附加属性等）                                  |
| `PathBBoxMode` | path bbox 精度模式：`accurate` / `fast`                             |

### 2.2 服务方法（在 `VerovioAsyncService` 上）

| 方法                                          | 返回                                          | 说明                               |
| ------------------------------------------- | ------------------------------------------- | -------------------------------- |
| `renderPageWithHitMap(pageIndex, {config})` | `Future<({String svg, PageHitMap hitMap})>` | 一次 RPC 同时拿 SVG 和 HitMap，**推荐入口** |
| `parseHitMap(svg, {pageIndex, config})`     | `Future<PageHitMap>`                        | 已有 SVG 字符串时单独解析                  |

> 这两个方法都在 isolate 内执行，主线程零阻塞。
> 同一 `(pageIndex, config)` 第二次调用会命中 page cache，\~0 开销。

### 2.3 命中查询（顶层纯函数）

| 函数                                                      | 返回                 | 说明                           |
| ------------------------------------------------------- | ------------------ | ---------------------------- |
| `hitTestPoint(hitMap, svgPoint, {types, topMost})`      | `ElementHit?`      | 点查询，多命中时按"最上层"返回             |
| `hitTestRect(hitMap, svgRect, {types, fullyContained})` | `List<ElementHit>` | 框选查询                         |
| `hitTestPointAll(hitMap, svgPoint, {types})`            | `List<ElementHit>` | 点查询返回所有命中                    |
| `snapToNearest(hitMap, svgPoint, {types})`              | `ElementHit?`      | 吸附查询：返回距离最近的元素，点击空白处不返回 null |
| `kBruteForceThreshold`                                  | `const int = 64`   | 元素数 < 此值时强制走暴力（小数据集索引开销大于收益） |

***

## 3. 详细签名

### 3.1 PageHitMap

```dart
class PageHitMap {
  final int pageIndex;
  final Size viewBox;                            // SVG 原始 viewBox 尺寸
  final UnmodifiableMapView<String, ElementHit> byId;   // 按 id 索引
  final UnmodifiableListView<ElementHit> byType;        // 按 emit 顺序（DFS 后序）
  final SpatialIndex? rTree;                     // 空间索引，可能为 null
  final Duration parseTime;                       // 解析耗时（调试用）
}
```

**插入顺序约定**：`byId` 是 `LinkedHashMap`，键序为 walker DFS 后序 —— 越深的元素越靠后，正好等同视觉"最上层"。`hitTestPoint(topMost: true)` 利用了这一点。

### 3.2 ElementHit

```dart
class ElementHit {
  final String id;            // 例如 "note-0000001234567890"
  final String type;          // "note" / "rest" / "measure" / ...
  final Rect bbox;            // SVG viewBox 坐标系下的 AABB
  final String? parentId;     // 最近的有 id 祖先（用来上溯小节）
  final Map<String, String>? extra;   // 按 ParseConfig.extraAttrs 抓取
}
```

### 3.3 ParseConfig

```dart
class ParseConfig {
  final Set<String>? captureClasses;   // null = 全部；默认 {note,rest,measure}
  final bool buildSpatialIndex;        // 默认 true（measureOnly 关闭）
  final Set<String> extraAttrs;        // 要额外抓取的属性名
  final PathBBoxMode pathMode;         // 默认 accurate
  final bool skipDecorative;           // 跳过装饰性子树
  int get configHash;                  // page cache key 用

  // 三个工厂
  const ParseConfig.defaultForInteractive();  // {note,rest,measure} + 索引
  const ParseConfig.measureOnly();             // 仅 measure，最快
  const ParseConfig.full();                    // 全 id（captureClasses=null）
}
```

### 3.4 命中函数

```dart
ElementHit? hitTestPoint(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
  bool topMost = true,
});

List<ElementHit> hitTestRect(
  PageHitMap hitMap,
  Rect svgRect, {
  Set<String>? types,
  bool fullyContained = false,
});

List<ElementHit> hitTestPointAll(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
});
```

```dart
ElementHit? snapToNearest(
  PageHitMap hitMap,
  Offset svgPoint, {
  Set<String>? types,
});
```

**坐标系**：`svgPoint` / `svgRect` 必须是 **SVG viewBox 坐标系**，不是屏幕像素。屏幕 ↔ SVG 换算由调用方负责（见第 5 节）。

***

## 4. Cookbook：5 个典型场景

### 4.1 渲染一页 + 解析

```dart
final svc = VerovioAsyncService(...);
await svc.loadData(meiContent);

final result = await svc.renderPageWithHitMap(0);
final String svg     = result.svg;
final PageHitMap map = result.hitMap;

print('共 ${map.byId.length} 个可命中元素');
```

### 4.2 点击一个音符 → 跳到该时间播放

```dart
GestureDetector(
  onTapUp: (e) async {
    // 把屏幕点变换回 SVG 坐标（见第 5 节工具函数）
    final svgPoint = screenToSvg(e.localPosition);

    final hit = hitTestPoint(map, svgPoint, types: {'note'});
    if (hit == null) return;

    // 反查时间 → 跳播放
    final timeMs = await svc.getTimeForElement(hit.id);
    audioPlayer.seekTo(timeMs);
  },
)
```

### 4.3 播放跟随高亮

```dart
// 播放器回调：每 16ms 刷新一次
Timer.periodic(const Duration(milliseconds: 16), (_) async {
  final currentMs = audioPlayer.positionMs;
  final ids = await svc.getElementsAtTime(currentMs);

  setState(() {
    _highlightedIds = ids.toSet();
  });
});

// 在 CustomPaint 里画高亮框
class HighlightPainter extends CustomPainter {
  final PageHitMap map;
  final Set<String> ids;
  final Matrix4 svgToScreen;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amber.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    for (final id in ids) {
      final hit = map.byId[id];
      if (hit == null) continue;
      final rect = MatrixUtils.transformRect(svgToScreen, hit.bbox);
      canvas.drawRect(rect, paint);
    }
  }
}
```

### 4.4 框选某区域所有音符

```dart
void onSelectionEnd(Rect screenRect) {
  final svgRect = screenRectToSvg(screenRect);
  final notes = hitTestRect(
    map,
    svgRect,
    types: {'note'},
    fullyContained: false,   // 框相交即命中
  );
  print('选中 ${notes.length} 个音符');
  for (final n in notes) {
    print('  ${n.id} 在小节 ${n.parentId}');
  }
}
```

### 4.5 点击任意位置吸附光标到最近音符

```dart
GestureDetector(
  onTapUp: (e) {
    final svgPoint = screenToSvg(e.localPosition);

    // 无论点在哪里，都会返回最近的音符，不会因空白处而返回 null
    final hit = snapToNearest(map, svgPoint, types: {'note'});
    if (hit == null) return; // hitMap 中根本没有 note 时才为 null

    setState(() => _cursor = hit);
    audioPlayer.seekTo(await svc.getTimeForElement(hit.id));
  },
)
```

**与 `hitTestPoint` 的区别：**

| 场景                 | `hitTestPoint`   | `snapToNearest` |
| ------------------ | ---------------- | --------------- |
| 点击落在 bbox 内        | 返回该元素            | 同左              |
| 点击落在两个 bbox 之间的空隙 | 返回 null          | 返回最近的那个元素       |
| 点击落在页面空白区域         | 返回 null          | 返回全页最近元素        |
| 性能（R-tree 路径）      | O(log n + k)     | O(log n)        |

### 4.6 只关心小节级跳播（最快配置）

```dart
final result = await svc.renderPageWithHitMap(
  0,
  config: const ParseConfig.measureOnly(),
);
// 解析耗时显著降低（大乐谱省 40%+），且不构建空间索引
```

***

## 5. 坐标系换算工具

HitMap 给的是 SVG viewBox 坐标，业务通常拿到的是屏幕坐标。两套工具：

### 5.1 手动换算（适合 `Stack` + 自定义 transform）

```dart
class SvgViewport {
  final Size viewBox;       // PageHitMap.viewBox
  final Size canvasSize;    // 屏幕上 SVG 显示区域
  final Offset offset;      // 平移
  final double scale;       // 缩放

  Offset screenToSvg(Offset screen) =>
      (screen - offset) / scale;

  Rect screenRectToSvg(Rect screen) => Rect.fromPoints(
        screenToSvg(screen.topLeft),
        screenToSvg(screen.bottomRight),
      );

  Rect svgRectToScreen(Rect svg) => Rect.fromLTRB(
        svg.left * scale + offset.dx,
        svg.top * scale + offset.dy,
        svg.right * scale + offset.dx,
        svg.bottom * scale + offset.dy,
      );
}
```

### 5.2 配合 `InteractiveViewer`

```dart
final controller = TransformationController();

InteractiveViewer(
  transformationController: controller,
  child: child,
);

// 屏幕点 → SVG 点
Offset screenToSvg(Offset screenPoint) {
  final inv = Matrix4.inverted(controller.value);
  final v = inv.transform3(Vector3(screenPoint.dx, screenPoint.dy, 0));
  return Offset(v.x, v.y);
}
```

> `vrv_flow_flutter`（交互层）会包好这一层，App 不用自己写。

***

## 6. 性能调优速查

| 想要什么    | 配置                                    | 代价                     |
| ------- | ------------------------------------- | ---------------------- |
| 跳小节最快   | `ParseConfig.measureOnly()`           | 解析省 40%+，但只能命中 measure |
| 默认命中    | `ParseConfig.defaultForInteractive()` | 平衡，**推荐**              |
| 全 id 索引 | `ParseConfig.full()`                  | 解析最慢，但任何 id 可查         |
| 跳过空间索引  | `buildSpatialIndex: false`            | n < 64 时本就走暴力，意义不大     |
| 抓播放时间属性 | `extraAttrs: {'data-time'}`           | +5–10% 解析时间            |
| 看一眼解析多久 | 读 `hitMap.parseTime`                  | 0 代价                   |

实测性能（M1 mac，详见基线文档）：

- 解析 1 页常规乐谱（default 模式 cold）：< 1ms
- `hitTestPoint` 平均：< 0.1µs
- `hitTestRect` 小框 / 大框平均：< 0.1µs
- `snapToNearest` 平均：< 0.5µs（R-tree branch-and-bound，O(log n)）

***

## 7. 边界与限制

- ✅ 支持 verovio 输出的所有 SVG 形状：`g/use/rect/line/polygon/polyline/ellipse/circle/path`
- ✅ 支持完整 transform 语法：`translate / scale / rotate / matrix / skewX / skewY`
- ✅ 跨页字形缓存（同字体 LRU 2000 条目）
- ⚠️ `<text>` 元素 bbox 采用字号粗估，精度低于其他元素（verovio 极少用）
- ⚠️ bbox 是几何外接矩形，不含 stroke 半宽。若需视觉精确边框，业务自行外扩 `strokeWidth / 2`
- ❌ 不支持 SVG 的 `filter / mask / clipPath / 动画`（verovio 也不输出）
- ❌ HitMap 是单页结果。多页连续视图请按页分别 hold

***

## 8. 错误与诊断

| 现象              | 可能原因             | 排查                                       |
| --------------- | ---------------- | ---------------------------------------- |
| `byId` 为空       | SVG 中没有匹配的 class | 检查 `ParseConfig.captureClasses` 是否过严     |
| 点击命不中           | 屏幕→SVG 坐标换算错     | 在已知 note 的 bbox 中心点直接调 `hitTestPoint` 验证 |
| `parseTime` 异常大 | 字形缓存未生效          | 同一 doc 第二页应显著加速；否则检查是否每次新建 service       |
| 高亮框偏移           | `viewBox` ≠ 渲染尺寸 | 用 `hitMap.viewBox` 而不是手填尺寸               |

打开诊断日志：

```dart
// transform_parser 内部使用 dart:developer 的 log，
// 在 DevTools 的 Logging 标签可看到 "Unknown transform function" 等 warning。
```

***

## 9. 跨 isolate 安全

- `PageHitMap` / `ElementHit` / `ParseConfig` / `Rect` / `Size` 全是不可变值类型，可直接通过 `SendPort` 在 isolate 间传递
- `SpatialIndex` 含 List 嵌套但无函数引用，同样可传
- `GlyphBBoxCache` 的全局静态 LRU 仅在 **同一 isolate 内**共享。主 isolate 与 worker isolate 的缓存是独立的（这是有意设计，避免锁）

***

## 10. 版本与兼容

- HitMap API 自 verovio\_flutter **0.2.0** 起稳定
- `PageHitMap.rTree` 字段曾在内部预留 `dynamic`，0.2.0 起为 `SpatialIndex?`，外部代码用 `??` 即可平滑
- 后续 minor 版本承诺：
  - 不删除现有公共类型 / 方法 / 字段
  - 新增 `ParseConfig` 字段时必有默认值
  - `ElementHit.type` 字符串保持与 verovio class 同步

***

## 11. 相关项目

- **vrv\_flow\_flutter**：交互层，包了 `VrvFlowView` widget，自带显示 + 命中 + 高亮 + 标注。日常 App 优先用它，本文档面向更底层的需求
- **verovio\_flutter**（本仓库）：底层 FFI + HitMap

***

## 附录 A：典型 ElementHit 类型清单

verovio SVG 中常见的 `class`（即 `ElementHit.type`）：

| type              | 含义        | 默认采集        |
| ----------------- | --------- | ----------- |
| `note`            | 音符        | ✅           |
| `rest`            | 休止符       | ✅           |
| `measure`         | 小节        | ✅           |
| `chord`           | 和弦组       | （`full` 模式） |
| `beam`            | 符干连接梁     | （`full` 模式） |
| `slur` / `tie`    | 圆滑线 / 延音线 | （`full` 模式） |
| `staff` / `layer` | 谱表 / 层    | （`full` 模式） |
| `system`          | 系统行       | （`full` 模式） |
| `dynam`           | 力度记号      | （`full` 模式） |
| `lyric`           | 歌词音节      | （`full` 模式） |

完整列表请参考 verovio 主仓 `data` 目录的类型定义。
