# verovio_flutter API 参考

`verovio_flutter` 是 Verovio C++ Toolkit 的 Flutter FFI 封装。

License：LGPL-3.0，见 [LICENSE](../LICENSE)

官方参考文档：[Verovio Toolkit Methods](https://book.verovio.org/toolkit-reference/toolkit-methods.html)

> 说明：本文以 `lib/verovio_flutter.dart` 和 `lib/src/*.dart` 的**实际代码**为准。
> 其中 `architecture.md` 里出现的 `create()` 示例、`VerovioException(errorCode/message)` 字段模型、以及 `VerovioPageCache.get(pageNo)` 等描述，和当前代码存在出入；以本文件和源码为准。

## Quick Start

```dart
import 'package:verovio_flutter/verovio_flutter.dart';

Future<void> main() async {
  // 1. 准备 Verovio 资源目录（首次启动会自动拷贝 assets/verovio_data/）
  final resourcePath = await VerovioResourceManager.ensureVerovioAssetsReady();

  // 2. 在 worker isolate 中创建异步 Toolkit 包装器
  final service = await VerovioAsyncService.spawn(resourcePath: resourcePath);

  try {
    // 3. 加载 MEI 文本
    const mei = '<mei xmlns="http://www.music-encoding.org/ns/mei"></mei>';
    await service.loadData(mei);

    // 4. 获取页数并渲染首页
    final pageCount = await service.pageCount;
    final svg = await service.renderToSvg(1);

    // 5. 把 SVG 交给 Flutter UI / WebView / 文件导出等后续流程
    print('页数：$pageCount');
    print(svg);
  } finally {
    // 6. 释放 native 资源（同时终止 worker isolate）
    await service.dispose();
  }
}
```


## 使用前说明

- `Verovio Toolkit` 本身**非线程安全**。本插件统一通过 `VerovioAsyncService`(基于 worker isolate 的异步封装)对外提供服务。
- 下游不要跨 isolate 传递 `Pointer`；也不要自己缓存 native 指针。
- `spawn()` 的 `resourcePath` 必须是**绝对路径**。
- 资源初始化遵循以下规则：
  1. 首次启动时，把 `assets/verovio_data/` 复制到应用支持目录；
  2. `VERSION` 文件与 `native/VEROVIO_VERSION` 不一致时会重拷贝；
3. `spawn()` 内部会先调用 `VerovioResourceManager.ensureVerovioAssetsReady()`，再创建 Toolkit。

---

## API 参考

### VerovioAsyncService

> 说明：以下签名以 `lib/src/verovio_async_service.dart` 为准。所有方法都返回 `Future`，由 worker isolate 串行执行,主线程不会被阻塞。

#### 生命周期与资源

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `static Future<VerovioAsyncService> spawn({required String resourcePath})` | `Toolkit()` | 启动 worker isolate 并创建 Verovio 实例。 | `resourcePath: String`，Verovio 资源目录绝对路径。 | 返回已创建的 `VerovioAsyncService`。 | `final service = await VerovioAsyncService.spawn(resourcePath: path);` | 否。参数非法会抛 `ArgumentError`，native 创建失败会抛 `StateError`。 |
| `Future<void> dispose()` | `~Toolkit()` | 销毁 native Toolkit 实例并终止 worker isolate。 | 无。 | `Future<void>`。 | `await service.dispose();` | 否。重复调用会直接返回。 |
| `Future<bool> setResourcePath(String resourcePath)` | `SetResourcePath` | 切换 Verovio 的资源目录。 | `resourcePath: String`，绝对路径。 | `true` 表示成功。 | `await service.setResourcePath(path);` | 是。native 返回 `false` 时抛 `VerovioException`。 |
| `Future<String> getResourcePath()` | `GetResourcePath` | 读取当前资源目录。 | 无。 | 当前资源目录路径字符串。 | `final path = await service.getResourcePath();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getVersion()` | `GetVersion` | 读取当前 Verovio 版本号。 | 无。 | 版本字符串。 | `final version = await service.getVersion();` | 是。native 返回空指针时抛 `VerovioException`。 |

#### 加载与解析

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `Future<void> loadData(String data)` | `LoadData` | 加载 MEI / MusicXML / 其他文本输入。 | `data: String`，输入文本。 | `Future<void>`。 | `await service.loadData(mei);` | 是。native 返回失败时抛 `VerovioException`。 |
| `Future<void> loadZipDataBase64(String base64Data)` | `LoadZipDataBase64` | 加载 base64 编码的压缩 MXL 数据。 | `base64Data: String`，base64 字符串。 | `Future<void>`。 | `await service.loadZipDataBase64(mxlBase64);` | 是。native 返回失败时抛 `VerovioException`。 |
| `Future<bool> loadZipDataBuffer(Uint8List bytes)` | `LoadZipDataBuffer` | 加载原始压缩 MXL 字节缓冲区。 | `bytes: Uint8List`，压缩字节。 | `true` 表示成功。 | `await service.loadZipDataBuffer(bytes);` | 是。native 返回 `false` 时抛 `VerovioException`。 |
| `Future<int> get pageCount` | `GetPageCount` | 读取当前内容的页数。 | 无。 | 页数整数。 | `final pages = await service.pageCount;` | 是。native 返回 `-1` 时抛 `VerovioException`。 |
| `Future<bool> setInputFrom(String inputFrom)` | `SetInputFrom` | 指定输入格式来源。 | `inputFrom: String`，例如 `mei`、`musicxml`。 | `true` 表示成功。 | `await service.setInputFrom('mei');` | 否。失败只会返回 `false`。 |
| `Future<bool> setOutputTo(String outputTo)` | `SetOutputTo` | 指定输出格式目标。 | `outputTo: String`，例如 `mei`、`humdrum`。 | `true` 表示成功。 | `await service.setOutputTo('mei');` | 否。失败只会返回 `false`。 |

#### Options

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `Future<String> getAvailableOptions()` | `GetAvailableOptions` | 获取全部可用选项及元数据。 | 无。 | JSON 字符串。 | `final json = await service.getAvailableOptions();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getDefaultOptions()` | `GetDefaultOptions` | 获取全部选项默认值。 | 无。 | JSON 字符串。 | `final json = await service.getDefaultOptions();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getOptions()` | `GetOptions` | 获取当前已设置的选项。 | 无。 | JSON 字符串。 | `final json = await service.getOptions();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<void> setOptionsJson(String json)` | `SetOptions` / `SetOptionsJson` | 用 JSON 一次性设置选项。 | `json: String`，Verovio 选项 JSON。 | `Future<void>`。 | `await service.setOptionsJson('{"scale":40}');` | 是。native 返回失败时抛 `VerovioException`。 |
| `Future<String> getOptionUsageString()` | `GetOptionUsageString` | 获取选项使用说明。 | 无。 | 说明文本。 | `final usage = await service.getOptionUsageString();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getDescriptiveFeatures(String jsonOptions)` | `GetDescriptiveFeatures` | 根据选项提取描述性特征。 | `jsonOptions: String`，JSON 选项字符串。 | JSON 字符串。 | `final features = await service.getDescriptiveFeatures('{}');` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<void> resetOptions()` | `ResetOptions` | 把选项恢复默认值。 | 无。 | `Future<void>`。 | `await service.resetOptions();` | 否。 |

#### 元素查询

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `Future<String> getElementAttr(String xmlId)` | `GetElementAttr` | 查询指定 `xml:id` 元素的属性。 | `xmlId: String`，元素 ID。 | JSON 字符串。 | `final attrs = await service.getElementAttr('n1');` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getElementsAtTime(int millisec)` | `GetElementsAtTime` | 查询某个时间点正在播放的元素。 | `millisec: int`，毫秒时间点。 | JSON 字符串。 | `final ids = await service.getElementsAtTime(1200);` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getExpansionIdsForElement(String xmlId)` | `GetExpansionIdsForElement` | 查询展开/原始元素对应的 ID 列表。 | `xmlId: String`，元素 ID。 | JSON 字符串。 | `final ids = await service.getExpansionIdsForElement('n1');` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getMidiValuesForElement(String xmlId)` | `GetMIDIValuesForElement` | 查询元素对应的 MIDI 数值。 | `xmlId: String`，元素 ID。 | JSON 字符串。 | `final midi = await service.getMidiValuesForElement('n1');` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getNotatedIdForElement(String xmlId)` | `GetNotatedIdForElement` | 查询谱面上对应的 notated ID。 | `xmlId: String`，元素 ID。 | 字符串。 | `final id = await service.getNotatedIdForElement('n1');` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getTimesForElement(String xmlId)` | `GetTimesForElement` | 查询元素的记谱时间和真实时间。 | `xmlId: String`，元素 ID。 | JSON 字符串。 | `final times = await service.getTimesForElement('n1');` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getId()` | `GetID` | 读取当前 Toolkit 实例 ID。 | 无。 | 字符串。 | `final id = await service.getId();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<int> getPageWithElement(String xmlId)` | `GetPageWithElement` | 查询元素所在页码。 | `xmlId: String`，元素 ID。 | 页码整数；找不到时通常为 `0`。 | `final page = await service.getPageWithElement('n1');` | 是。native 返回 `-1` 时抛 `VerovioException`。 |
| `Future<int> getTimeForElement(String xmlId)` | `GetTimeForElement` | 查询元素的时间位置。 | `xmlId: String`，元素 ID。 | 毫秒整数。 | `final time = await service.getTimeForElement('n1');` | 是。native 返回 `-1` 时抛 `VerovioException`。 |

#### 渲染与导出

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `Future<String> renderToSvg(int pageNo, {bool xmlDeclaration = false})` | `RenderToSVG` | 把指定页渲染成 SVG。 | `pageNo: int`，页码；`xmlDeclaration: bool`，是否输出 XML 声明。 | SVG 字符串。 | `final svg = await service.renderToSvg(1);` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> renderToMidi()` | `RenderToMIDI` | 导出 MIDI 内容。 | 无。 | base64 编码的 MIDI 字符串。 | `final midiBase64 = await service.renderToMidi();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<Uint8List> renderToMidiBytes()` | 无（Dart 辅助方法） | 将 `renderToMidi()` 的 base64 结果直接解码成字节。 | 无。 | `Uint8List`。 | `final midiBytes = await service.renderToMidiBytes();` | 否。若 base64 非法，会抛 `FormatException`。 |
| `Future<String> renderToPae()` | `RenderToPAE` | 导出 PAE 文本。 | 无。 | 字符串。 | `final pae = await service.renderToPae();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> renderToTimemap({String jsonOptions = ''})` | `RenderToTimemap` | 导出时间映射。 | `jsonOptions: String`，JSON 选项字符串，可为空。 | JSON 字符串。 | `final tm = await service.renderToTimemap();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> renderToExpansionMap()` | `RenderToExpansionMap` | 导出展开映射。 | 无。 | JSON 字符串。 | `final map = await service.renderToExpansionMap();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> renderData(String data, String jsonOptions)` | `RenderData` | 一步完成“设置 + 加载 + 渲染首屏”。 | `data: String`，输入文本；`jsonOptions: String`，选项 JSON。 | SVG 字符串。 | `final svg = await service.renderData(mei, '{}');` | 是。native 返回空指针时抛 `VerovioException`。 |

#### 转换

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `Future<String> getHumdrum()` | `GetHumdrum` | 读取当前 Humdrum 缓冲区。 | 无。 | Humdrum 字符串。 | `final humdrum = await service.getHumdrum();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> getMei(String jsonOptions)` | `GetMEI` | 把当前内容导出为 MEI。 | `jsonOptions: String`，JSON 选项字符串。 | MEI XML 字符串。 | `final mei = await service.getMei('{}');` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> convertHumdrumToHumdrum(String data)` | `ConvertHumdrumToHumdrum` | 对 Humdrum 输入做过滤/转换。 | `data: String`，Humdrum 文本。 | Humdrum 字符串。 | `final out = await service.convertHumdrumToHumdrum(humdrum);` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> convertHumdrumToMidi(String data)` | `ConvertHumdrumToMIDI` | 把 Humdrum 转成 base64 MIDI。 | `data: String`，Humdrum 文本。 | base64 MIDI 字符串。 | `final midiBase64 = await service.convertHumdrumToMidi(humdrum);` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<Uint8List> convertHumdrumToMidiBytes(String data)` | 无（Dart 辅助方法） | 将 `convertHumdrumToMidi()` 的 base64 结果直接解码成字节。 | `data: String`，Humdrum 文本。 | `Uint8List`。 | `final midiBytes = await service.convertHumdrumToMidiBytes(humdrum);` | 否。若 base64 非法，会抛 `FormatException`。 |
| `Future<String> convertMeiToHumdrum(String data)` | `ConvertMEIToHumdrum` | 把 MEI / XML 转成 Humdrum。 | `data: String`，MEI 或 XML 文本。 | Humdrum 字符串。 | `final humdrum = await service.convertMeiToHumdrum(mei);` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<String> validatePae(String data)` | `ValidatePAE` | 校验 Plaine & Easie 输入。 | `data: String`，PAE 文本。 | 校验结果字符串。 | `final result = await service.validatePae(pae);` | 是。native 返回空指针时抛 `VerovioException`。 |

#### 布局与编辑

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `Future<int> getScale()` | `GetScale` | 读取当前缩放比例。 | 无。 | 整数缩放值。 | `final scale = await service.getScale();` | 是。native 返回 `-1` 时抛 `VerovioException`。 |
| `Future<bool> setScale(int scale)` | `SetScale` | 设置缩放比例。 | `scale: int`，缩放值。 | `true` 表示成功。 | `await service.setScale(40);` | 否。失败只会返回 `false`。 |
| `Future<bool> select(String selectionJson)` | `Select` | 选中一组元素或位置。 | `selectionJson: String`，Verovio selection JSON。 | `true` 表示成功。 | `await service.select('{"ids":["n1"]}');` | 否。失败只会返回 `false`。 |
| `Future<bool> edit(String editorAction)` | `Edit` | 执行编辑动作。 | `editorAction: String`，编辑动作字符串。 | `true` 表示成功。 | `await service.edit('delete');` | 否。失败只会返回 `false`。 |
| `Future<String> editInfo()` | `EditInfo` | 读取编辑信息。 | 无。 | 字符串。 | `final info = await service.editInfo();` | 是。native 返回空指针时抛 `VerovioException`。 |
| `Future<void> redoLayout({String jsonOptions = ''})` | `RedoLayout` | 重新布局，并可附带 JSON 选项。 | `jsonOptions: String`，可为空。 | `Future<void>`。 | `await service.redoLayout(jsonOptions: '{}');` | 否。 |
| `Future<void> redoPagePitchPosLayout()` | `RedoPagePitchPosLayout` | 只重算当前页音高垂直位置。 | 无。 | `Future<void>`。 | `await service.redoPagePitchPosLayout();` | 否。 |
| `Future<void> resetXmlIdSeed(int seed)` | `ResetXmlIdSeed` | 重置 `xml:id` 种子。 | `seed: int`，整数种子。 | `Future<void>`。 | `await service.resetXmlIdSeed(1);` | 否。 |

#### 日志

| 方法签名 (Dart) | 对应 Verovio Toolkit 方法名 | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | VerovioException |
| --- | --- | --- | --- | --- | --- | --- |
| `Future<String> getLog()` | `GetLog` | 读取最近一次错误或日志。 | 无。 | 日志字符串。 | `final log = await service.getLog();` | 是。native 返回空指针时抛 `VerovioException`。 |

#### 说明

- `VerovioAsyncService` 的每个方法都会返回 `Future`,实际的 FFI 调用在 worker isolate 中串行执行。
- 对于返回 `String` 的方法，如果 native 失败，通常会抛 `VerovioException(method: ..., log: ...)`，其中 `log` 来自 worker 中的 `getLog()`。
- 对于返回 `bool` 的方法，`false` 一般表示 native 拒绝或参数不合法；这些方法**不会**自动抛 `VerovioException`。
- `loadData()` / `loadZipDataBase64()` / `renderToSvg()` 等方法的失败信息，通常可以直接看异常里的 `log`。
- `dispose()` 会先通知 worker 销毁 native 实例，再终止 isolate;重复调用安全。

---

### VerovioResourceManager

**作用**：把 `assets/verovio_data/` 解压/复制到应用支持目录，供 `SetResourcePath` 使用。

**使用方式**：通常由 `VerovioAsyncService.spawn()` 内部自动调用，下游一般无需手动操作。

| 方法签名 (Dart) | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `static Future<String> ensureVerovioAssetsReady()` | 确保 Verovio 资源已复制到应用支持目录，并返回目标目录路径。 | 无。 | 返回资源目录绝对路径。 | `final path = await VerovioResourceManager.ensureVerovioAssetsReady();` | 若资源复制失败会抛 `StateError`。 |

**资源初始化说明**

- 首次运行：从 asset bundle 把 `assets/verovio_data/` 复制到 `getApplicationSupportDirectory()/verovio_data/`。
- 版本变化：读取 `native/VEROVIO_VERSION`，如果和目标目录里的 `VERSION` 不一致，就会删除旧目录并重新复制。
- 一般只需要把 `ensureVerovioAssetsReady()` 的返回值传给 `VerovioAsyncService.spawn(resourcePath: ...)`。

---

### VerovioPageCache

**作用**：分页缓存已渲染的 SVG 字符串。

**使用方式**：用 `getOrRender(...)` 获取页面内容；命中缓存时直接返回，miss 时调用你传入的 `render` 回调。缓存 key 由 `data + optionsJson + pageNo` 组成。

| 方法签名 (Dart) | 作用 | 参数说明 | 返回值说明 | 简短使用示例 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `VerovioPageCache({int capacity = 32})` | 创建一个页面缓存。 | `capacity: int`，缓存容量，必须大于 0。 | `VerovioPageCache` 实例。 | `final cache = VerovioPageCache(capacity: 32);` | 容量满时淘汰最旧项。 |
| `Future<String> getOrRender({required String data, required String optionsJson, required int pageNo, required Future<String> Function() render})` | 先查缓存，未命中则执行 `render()` 并写入缓存。 | `data: String`，输入内容；`optionsJson: String`，选项 JSON；`pageNo: int`，页码；`render: Future<String> Function()`，渲染回调。 | 返回 SVG 字符串。 | `final svg = await cache.getOrRender(data: mei, optionsJson: '{}', pageNo: 1, render: () async => service.renderToSvg(1));` | 缓存键按 `data` / `optionsJson` / `pageNo` 计算。 |
| `void invalidateAll()` | 清空全部缓存。 | 无。 | `void`。 | `cache.invalidateAll();` | 适合切换文档或选项后调用。 |
| `int get length` | 读取当前缓存条目数。 | 无。 | 条目数。 | `final n = cache.length;` | 只反映内存中的缓存项数量。 |

**实现要点**

- 缓存是内存中的 `LinkedHashMap`。
- 读取命中项时，会把该项移动到队尾，实现 LRU 行为。
- 超过 `capacity` 时，会删除最旧项。
- 该类本身不持有 `VerovioAsyncService`，你可以把任意渲染回调传给它。

---

### VerovioException

`VerovioException` 是这个包里统一使用的 native 失败异常包装类。

**构造函数**

```dart
VerovioException({required String method, String log = ''})
```

**字段**

- `method`：`String`，触发异常的方法名。
- `log`：`String`，native `GetLog()` 取回的最近日志，通常包含 Verovio 的详细错误原因。

**补充说明**

- 当前代码里**没有** `errorCode(int)` / `message(String)` 字段；这是 `architecture.md` 旧稿里的描述方式。
- 常见触发场景：`loadData()` 传入无效内容、`renderToSvg()` 时未加载数据、资源路径未初始化、native 返回空指针或 `-1` 等。
- 打印出来通常长这样：`VerovioException(method: loadData, log: ...)`。

---

## 未暴露的 Toolkit 方法

下面这些是 `architecture.md` 里列出的“已跳过”项，当前 Dart 层**没有**公开它们：

| Toolkit 方法名 | 为什么不在 Dart 层暴露 |
| --- | --- |
| `LoadFile` | 文件路径型 API 与 Flutter 侧的 asset / sandbox 路径管理重复，Dart 层已统一用字符串/字节输入。 |
| `SaveFile` | 属于写文件副作用 API，包内更适合由下游自己决定保存位置和格式。 |
| `RenderToSVGFile` | 这是“直接写文件”的变体；Flutter 更常用 `renderToSvg()` 后自行落盘。 |
| `RenderToMIDIFile` | 同上，文件输出责任应留给 Dart/Flutter 层。 |
| `RenderToPAEFile` | 同上。 |
| `RenderToTimemapFile` | 同上。 |
| `RenderToExpansionMapFile` | 同上。 |
| `GetHumdrumFile` | 文件路径型读取接口在 Flutter 插件里不如字符串接口通用。 |
| `ValidatePAEFile` | 与 `validatePae(String)` 功能重叠，字符串接口更适合插件调用。 |
| `PrintOptionUsage` | 这是打印到 stdout/stderr 的命令式接口，不适合 Flutter 包；已由 `getOptionUsageString()` 替代。 |
| `Toolkit(bool initFont)` | 这是构造阶段的底层初始化细节；当前包统一通过 `spawn(resourcePath: ...)` 和资源管理器完成初始化。 |

---

## 相关链接

- Verovio 官方 Toolkit 方法文档：<https://book.verovio.org/toolkit-reference/toolkit-methods.html>
- 本仓库 LICENSE：[LICENSE](../LICENSE)
