# verovio_flutter

**Render beautiful sheet music in your Flutter app — from MEI, MusicXML, ABC, Humdrum or PAE, straight to SVG.**

[![License: LGPL-3.0](https://img.shields.io/badge/License-LGPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue.svg)]()
[![Verovio](https://img.shields.io/badge/Verovio-6.2.1-orange.svg)]()

Language: [English](README.md) | [中文](README_CN.md)

<p align="center">
  <img src="doc/images/iphone-demo.png" alt="verovio_flutter demo on iPhone" height="360"/>
</p>

`verovio_flutter` is a Flutter FFI plugin that embeds [Verovio](https://www.verovio.org/) — the open-source music notation engraving library used by the MEI community, RISM, and the Music Encoding Initiative — directly into your Android and iOS apps. No server, no WebView, no network. Just native engraving on device.

## Why use it

- **Real engraving, not just rendering** — Verovio lays out music with publication quality (beams, slurs, ties, articulations, lyrics, multi-voice, page breaks).
- **Works offline** — everything runs natively on the device via FFI. No HTTP, no JS bridge.
- **Multiple input formats** — MEI, MusicXML, Humdrum, ABC, Plaine & Easie.
- **SVG output** — vector graphics that scale on any screen, embed in your own widgets, export to PDF, or post-process freely.
- **Isolate-friendly** — `VerovioAsyncService` runs the toolkit on a worker isolate so rendering never blocks your UI.
- **Drop-in size** — ~7 MB per ABI after `--split-per-abi` on Android.

## Install

```yaml
dependencies:
  verovio_flutter: ^0.1.1
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:verovio_flutter/verovio_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Unpack the Verovio font/data assets once.
  final resourcePath = await VerovioResourceManager.ensureVerovioAssetsReady();

  // 2. Spawn a worker isolate that owns the toolkit.
  final service = await VerovioAsyncService.spawn(resourcePath: resourcePath);

  // 3. Feed it MEI / MusicXML / ABC / Humdrum.
  await service.loadData('''<mei xmlns="http://www.music-encoding.org/ns/mei">
    <music><body><mdiv><score><section/></score></mdiv></body></music>
  </mei>''');

  // 4. Get an SVG string for any page and draw it.
  final svg = await service.renderToSvg(1);

  // Render `svg` with any SVG widget of your choice
  // (e.g. flutter_svg, jovial_svg, a WebView, or your own renderer).
  print(svg);
}
```

`VerovioAsyncService` runs every FFI call on a dedicated worker isolate, so your UI thread stays responsive. This is the only recommended entry point.

A complete runnable example lives in [`example/`](example).

### Optional page cache

If you render the same page repeatedly, `VerovioPageCache` can keep SVG strings in memory:

```dart
final cache = VerovioPageCache(capacity: 32);
final svg = await cache.getOrRender(
  data: mei,
  optionsJson: '{}',
  pageNo: 1,
  render: () => service.renderToSvg(1),
);
```

## Platform support

| Platform | Minimum version | Architectures |
|----------|-----------------|---------------|
| Android  | API 21          | arm64-v8a / x86_64 |
| iOS      | 13.0            | arm64 (device) / arm64 + x86_64 (simulator) |

## Size

| Component | Size |
|-----------|------|
| `android/src/main/jniLibs` | 14 MB |
| `ios/Frameworks/VerovioFFI.xcframework` | 8.6 MB |
| `assets/verovio_data` (fonts + schemas) | 11 MB |
| **Bundled total** | **33.6 MB** |

Per-ABI install footprint on Android with `--split-per-abi`: **~6.8 MB** (`arm64-v8a`) / **~7.2 MB** (`x86_64`) before APK compression.

## API reference

See [`doc/api.md`](doc/api.md) for the full `VerovioAsyncService` surface (options, page navigation, MIDI export, time-map, etc.), along with `VerovioResourceManager` and `VerovioPageCache`.

## Troubleshooting

- **`spawn()` throws `ArgumentError`**: make sure `resourcePath` is an absolute path returned by `VerovioResourceManager.ensureVerovioAssetsReady()`.
- **`VerovioException` after `loadData()`**: inspect `exception.log`; Verovio usually explains the parse or layout error there.
- **Empty output / `pageCount == 0`**: confirm the input is a supported score format and that the data is not empty.
- **Package score is lower than expected on pub.dev**: republish after documentation changes, then wait for pub.dev to reanalyze the package.

## Version mapping

| verovio_flutter | Verovio upstream |
|-----------------|------------------|
| 0.1.0           | `version-2.7.1-10372-g8100cb396` (`8100cb39604d40102a9c2ce75719136f3fb52a77`) |
| 0.1.1           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |

## License

LGPL-3.0. Verovio is LGPL-3.0; any derivative work must comply with the same obligations. You can use this plugin in closed-source apps as long as you respect the LGPL dynamic-linking rules.

## Maintainer guide

<details>
<summary>Build and sync commands</summary>

- Clone with submodules: `git clone --recurse-submodules https://github.com/csa8820/verovio_flutter`
- Rebuild Android `.so`: `bash tool/build_android_so.sh`
- Rebuild iOS `.xcframework`: `bash tool/build_ios_xcframework.sh`
- Sync upstream Verovio sources: `bash tool/sync_verovio_sources.sh`
- GitHub Actions CI runs Android + iOS build validation on PRs and pushes to `main`.

</details>

## Credits

Built on top of [Verovio](https://github.com/rism-digital/verovio) by the RISM Digital Center. This plugin only provides the Flutter / FFI glue — all the engraving magic is theirs.
