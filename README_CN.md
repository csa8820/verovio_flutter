# verovio_flutter

[![License: LGPL-3.0](https://img.shields.io/badge/License-LGPL--3.0-blue.svg)](LICENSE)

`verovio_flutter` 是基于 Verovio 的 Flutter FFI 插件，遵循 LGPL-3.0。  
任何派生作品也必须遵守同样的 LGPL-3.0 许可证要求。

Language: [English](README.md) | [中文](README_CN.md)

> 当前发布树体积快照：
>
> - `android/src/main/jniLibs`: `14M`
> - `ios/Frameworks/VerovioFFI.xcframework`: `8.6M`
> - `assets/verovio_data`: `11M`
> - **总计：** `33.6M`
>
> Android 使用 `--split-per-abi` 后，单个 APK 的增量体积大约是 `6.8M`（`arm64-v8a`）和 `7.2M`（`x86_64`），未计入 APK 压缩差异。

## 安装

```yaml
dependencies:
  verovio_flutter:
    git:
      url: https://github.com/csa8820/verovio_flutter
      ref: v0.1.0
```

## 最小使用示例

示例工程 `example/lib/main.dart` 是一个最小的 SVG 展示器。下面的代码演示与其一致的核心流程：创建 `VerovioService`、加载 MEI/XML、渲染 SVG，然后在 Flutter 中展示。

```dart
import 'package:flutter/material.dart';
import 'package:verovio_flutter/verovio_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final resourcePath = await VerovioResourceManager.ensureVerovioAssetsReady();
  final service = await VerovioService.spawn(resourcePath: resourcePath);
  service.loadData('''<mei xmlns="http://www.music-encoding.org/ns/mei">
  <music><body><mdiv><score><section/></score></mdiv></body></music>
</mei>''');

  final svg = service.renderToSvg(1);
  runApp(MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('verovio_flutter demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(svg),
      ),
    ),
  ));
}
```

## 平台支持

| 平台 | 最低版本 | 架构 |
|------|----------|------|
| Android | API 21 | arm64-v8a / x86_64 |
| iOS | 13.0 | arm64(device) / arm64+x86_64(simulator) |

## 版本对应关系

`verovio_flutter 0.1.0 → Verovio version-2.7.1-10372-g8100cb396`

## 维护者指南

<details>
<summary>构建与同步命令</summary>

- 初始化 submodule：
  `git clone --recurse-submodules https://github.com/csa8820/verovio_flutter`
- 重新构建 Android `.so`：
  `bash tool/build_android_so.sh`
- 重新构建 iOS `.xcframework`：
  `bash tool/build_ios_xcframework.sh`
- 同步资源：
  `bash tool/sync_verovio_sources.sh`

</details>

