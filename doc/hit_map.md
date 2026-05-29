# HitMap 使用说明（速览）

> 一句话：把 verovio 输出的 SVG 变成一张 **"id → 矩形位置"** 的查找表，让 Flutter 知道点哪儿是哪个音符。
>
> 状态：**已交付**（verovio\_flutter 0.2.0+）

文档导航：

- 5 分钟上手 → 本文（继续往下）
- 完整 API 参考 + Cookbook → [hit\_map\_api.md](./hit_map_api.md)

***

## 1. 它解决什么问题

光有 SVG 字符串，Flutter 不知道：

- 用户点屏幕上某个点 → 点中的是哪个音符？
- 播放到第 3 拍 → 哪个音符要高亮？框画在哪？
- 用户拖拽框选 → 框里有哪些音符？

HitMap 就是这张查找表，所有交互都靠它。

***

## 2. 输入与输出

### 输入

verovio 渲染出的一页 SVG 字符串（你已经在用的 `vrv_ffi_render_to_svg` 返回值）。

```xml
<svg viewBox="0 0 2100 2970">
  <g class="page-margin" transform="translate(100, 100)">
    <g class="measure" id="measure-001">
      <g class="note" id="note-001">
        <use xlink:href="#E0A4" x="200" y="80"/>
      </g>
      <g class="note" id="note-002">
        <use xlink:href="#E0A4" x="280" y="80"/>
      </g>
    </g>
  </g>
</svg>
```

### 输出

一个 `PageHitMap` 对象，包含每个 id 的矩形位置：

```dart
PageHitMap {
  viewBox: Size(2100, 2970),
  byId: {
    "measure-001": ElementHit(type: "measure", bbox: Rect(300,180,180,15)),
    "note-001":    ElementHit(type: "note",    bbox: Rect(300,180, 20,15)),
    "note-002":    ElementHit(type: "note",    bbox: Rect(380,180, 20,15)),
  }
}
```

矩形坐标是 **SVG viewBox 坐标系**（不是屏幕像素）。屏幕显示时按你的缩放/平移矩阵换算。

***

## 3. 完整 API

只有 5 个东西要记：

### 3.1 渲染一页 + 拿 HitMap

```dart
final result = await service.renderPageWithHitMap(pageIndex);
final String svg       = result.svg;
final PageHitMap hitMap = result.hitMap;
```

### 3.2 已有 SVG 字符串，只想解析

```dart
final hitMap = await service.parseHitMap(svgString);
```

### 3.3 点击命中

```dart
final ElementHit? hit = hitTestPoint(hitMap, svgPoint);
print(hit?.id);     // "note-001"
print(hit?.type);   // "note"
print(hit?.bbox);   // Rect(300, 180, 20, 15)
```

### 3.4 框选命中

```dart
final List<ElementHit> hits = hitTestRect(
  hitMap,
  Rect.fromLTWH(0, 0, 500, 300),
  types: {'note'},               // 只要 note，不要 measure
);
```

### 3.5 吸附到最近元素

点击位置不在任何 bbox 内时，`hitTestPoint` 返回 null；`snapToNearest` 则永远返回距离最近的元素，适合光标吸附、触摸定位等场景：

```dart
final ElementHit? hit = snapToNearest(hitMap, svgPoint, types: {'note'});
// hit 不会因点击了空白处而为 null（只要 hitMap 含有 note）
```

***

## 4. 配置选项

默认采集 `note / rest / measure`，已能覆盖 90% 场景。需要调整时传 `ParseConfig`：

```dart
// 只关心小节级跳播放，最快
service.renderPageWithHitMap(0, config: ParseConfig.measureOnly());

// 要 beam / slur / chord 等所有 id
service.renderPageWithHitMap(0, config: ParseConfig.full());

// 自定义
service.renderPageWithHitMap(0, config: ParseConfig(
  captureClasses: {'note', 'measure', 'lyric'},
  extraAttrs: {'data-time'},     // 把每个元素的 data-time 也抓出来
  buildSpatialIndex: true,       // 大乐谱必开，框选/点击 O(log n)
));
```

***

## 5. 典型业务场景

### 5.1 播放跟随高亮

```dart
// 播放器回调：当前时间 → 当前 element id
final currentNoteId = await service.getElementsAtTime(currentMs);

// 在 widget 里设置高亮（vrv_flow_flutter 提供的 VrvFlowView）
flowView.highlightedIds = {currentNoteId};
```

### 5.2 点击查时间

```dart
GestureDetector(
  onTapUp: (e) async {
    final svgPoint = screenToSvg(e.localPosition);     // 你的缩放矩阵反解
    final hit = hitTestPoint(hitMap, svgPoint, types: {'note'});
    if (hit != null) {
      final timeMs = await service.getTimeForElement(hit.id);
      audioPlayer.seekTo(timeMs);
    }
  },
)
```

### 5.3 点击任意位置吸附光标到最近音符

```dart
GestureDetector(
  onTapUp: (e) {
    final svgPoint = screenToSvg(e.localPosition);
    final hit = snapToNearest(hitMap, svgPoint, types: {'note'});
    if (hit != null) {
      setState(() => _cursor = hit);
    }
  },
)
```

### 5.4 框选删除某小节内所有音符

```dart
final notes = hitTestRect(hitMap, selectionRect, types: {'note'});
for (final n in notes) {
  // n.id, n.bbox, n.parentId（其所在 measure 的 id）
}
```

***

## 6. 坐标系换算

HitMap 给的是 **SVG viewBox 坐标**。屏幕上的点要换算回去：

```dart
// 屏幕 → SVG
final svgPoint = (screenPoint - canvasOffset) / scale;

// SVG → 屏幕（画高亮框时用）
final screenRect = Rect.fromLTRB(
  hit.bbox.left  * scale + canvasOffset.dx,
  hit.bbox.top   * scale + canvasOffset.dy,
  hit.bbox.right * scale + canvasOffset.dx,
  hit.bbox.bottom* scale + canvasOffset.dy,
);
```

如果用 `InteractiveViewer`，可以从其 `TransformationController.value` 拿到矩阵，直接 `Matrix4.inverted().transform3()` 处理。

`vrv_flow_flutter` 的 `VrvFlowView` 会包好这层，你不用手算。

***

## 7. 性能预期

| 乐谱规模      | 解析耗时（M1 Mac） | 解析耗时（中端手机） |
| --------- | ------------ | ---------- |
| 5 小节      | ≤ 5 ms       | ≤ 15 ms    |
| 30 小节钢琴谱  | ≤ 30 ms      | ≤ 80 ms    |
| 50 小节合唱总谱 | ≤ 120 ms     | ≤ 300 ms   |

解析在 isolate 内执行，不阻塞主线程。同一文档第二页起，字形 bbox 已缓存，耗时再降 \~30%。

***

## 8. 限制

- 只支持 verovio 输出的 SVG（依赖其固定的 id/class 命名）
- 不支持 SVG 的 filter / mask / clipPath / 动画（verovio 也不输出这些）
- text 元素 bbox 用字号粗估，精度低于其他元素（verovio 极少用 text）
- bbox 是元素的**几何外接矩形**，不含 stroke 宽度的一半（如果需要精确视觉边框，自行外扩 `strokeWidth / 2`）
