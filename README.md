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
  verovio_flutter: ^0.3.1
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

| Platform | Minimum version | Architectures | Notes |
|----------|-----------------|---------------|-------|
| Android  | API 21          | arm64-v8a / x86_64 | Native FFI |
| iOS      | 13.0            | arm64 (device) / arm64 + x86_64 (simulator) | Native FFI |
| Web      | All modern browsers | N/A | WASM via Web Worker |
| WeChat mini-app | — | N/A | WASM via inline backend (no Worker) |

### Web support (WASM)

`verovio_flutter` fully supports **Flutter Web** via WebAssembly. The public API is compatible across all platforms — your code works without changes on mobile and web, with a few Web-only no-op methods noted below.

**Key features:**
- Renders SVG in a Web Worker (non-blocking)
- All 38 Verovio API actions (render, MIDI, time-map, hit_map, ZIP/MXL load, edit operations)
- Hit-testing with `renderPageWithHitMap()` and `hitTestPoint()`
- Page caching via `VerovioPageCache`
- No server or HTTP — everything local

**Build for Web:**

1. Build the Verovio Web Worker and Flutter app:
   ```bash
   cd path/to/verovio_flutter
   bash tool/build_web.sh
   ```
2. Run or serve:
   ```bash
   # Option 1: flutter run
   flutter run -d chrome

   # Option 2: Manual serve
   python3 -m http.server --directory example/build/web 8000
   # Then open http://localhost:8000
   ```

**Using it in your own app (Web):**

The package spawns its own Web Worker and loads the WASM toolkit by itself —
**no bootstrap `<script>` is required** in your `index.html`. You only need two
files present at your app's web root (copy them from this package's `web/`):

```
web/
├── verovio_worker.dart.js              # compiled Verovio worker
└── verovio/
    └── verovio-toolkit-wasm.js         # official Verovio WASM toolkit
```

`dart compile js` for the worker is run for you by `tool/build_web.sh`,
which stages `verovio_worker.dart.js` into `example/web/`. For your own app,
copy both files into your `web/` folder (so they are picked up by both
`flutter run -d chrome` and `flutter build web`).

**Optional configuration.** If you serve those assets from non-default
locations, set a global config _before_ Flutter boots in `web/index.html`:

```html
<script>
  window.verovioFlutterConfig = {
    workerUrl: 'verovio_worker.dart.js',           // default
    wasmUrl: 'verovio/verovio-toolkit-wasm.js',    // default, resolved relative to the worker
  };
</script>
```

> On Web the `resourcePath` passed to `VerovioAsyncService.spawn(...)` is
> ignored — fonts and resources are embedded in the WASM module. Any non-empty
> string satisfies the cross-platform API.

**Version alignment:**

| Component | Version | Notes |
|-----------|---------|-------|
| Native (Android/iOS) | Verovio 6.2.1 | Built from [upstream tag](https://github.com/rism-digital/verovio) |
| Web (WASM) | Verovio 6.2.0 | Official [npm package](https://www.npmjs.com/package/verovio) — functionally equivalent to native 6.2.1 |

> **Why 6.2.0 for Web?** The official Verovio npm package only ships 6.2.0 WASM; no 6.2.1 JS/WASM release exists. The emscripten outputs (6.2.0 vs 6.2.1) are identical in behavior.

**Known limitations on Web:**

The following methods are **no-ops** on Web (return placeholder values or do nothing):
- `setScale()` / `getScale()` — WASM toolkit has no corresponding method
- `setResourcePath()` / `getResourcePath()` — fonts are embedded in WASM; resource path is unused
- `setInputFrom()` / `setOutputTo()` — file I/O not applicable to WASM
- `spawn()` — initialization is handled transparently on Web

All other methods (rendering, MIDI, hit-testing, editing, etc.) work identically to the native implementation.

**Performance notes:**
- SVG rendering: 50–200 ms per page (depends on score complexity)
- Hit-map generation: included in render time; cached by `VerovioPageCache`
- Memory: WASM heap managed by browser; `dispose()` frees Worker resources
- Large scores: watch browser DevTools Memory tab for heap usage patterns

### WeChat mini-app support

The Web backend also runs inside the **WeChat mini-program** logic layer, which
has no Web Worker. The package detects this automatically and switches to an
**inline backend** (`worker_client_inline_web.dart`) that runs the toolkit on the
same thread — no API changes required.

**How detection works:**
- If the host sets `window.verovioFlutterConfig.forceInline = true`, the inline
  backend is used.
- Otherwise, if the `WXWebAssembly` global is present (WeChat mini-program logic
  layer), the inline backend is used.
- In a normal browser, the standard Web Worker backend is used.

**Prebuilt mini-app assets:**

The standard `verovio-toolkit-wasm.js` embeds the WASM binary as a huge base64
string, which exceeds the mini-program package size limit. This package ships a
slimmed-down glue file plus a brotli-compressed binary so you don't have to
build them yourself:

```
web/verovio/
├── verovio-weapp.js      # slimmed glue (WASM loaded externally)
└── verovio.wasm.br       # brotli-compressed WASM binary
```

Copy both files into your mini-program project, and point `wx.__verovioWasmPath`
at the `.wasm.br` asset before loading the glue.

## Size

| Component | Size |
|-----------|------|
| `android/src/main/jniLibs` | 14 MB |
| `ios/Frameworks/VerovioFFI.xcframework` | 14.8 MB |
| `assets/verovio_data` (fonts + schemas) | 11.4 MB |
| **Bundled total** | **40.2 MB** |

Per-ABI install footprint on Android with `--split-per-abi`: **~6.8 MB** (`arm64-v8a`) / **~7.2 MB** (`x86_64`) before APK compression.

> Note: the iOS binary size increased after changing the packaging flow to ship a fuller `.xcframework` build.

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
| 0.1.2           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |
| 0.1.3           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |
| 0.1.4           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |
| 0.1.6           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |
| 0.2.0           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |
| 0.2.1           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |
| 0.3.0           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |
| 0.3.1           | `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`) |

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
