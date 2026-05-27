# verovio_flutter

**Render beautiful sheet music in your Flutter app — from MEI, MusicXML, ABC, Humdrum or PAE, straight to SVG.**

[![License: LGPL-3.0](https://img.shields.io/badge/License-LGPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue.svg)]()
[![Verovio](https://img.shields.io/badge/Verovio-6.2.1-orange.svg)]()

Language: [English](README.md) | [中文](README_CN.md)

<p align="center">
  <img src="doc/images/hero.png" alt="Chopin — Mazurka in F-sharp Minor, Op.6 No.1, engraved by verovio_flutter" width="600"/>
  <br/>
  <sub><i>Chopin — Mazurka Op.6 No.1, rendered by <code>verovio_flutter</code> from MEI source.</i></sub>
</p>

`verovio_flutter` is a Flutter FFI plugin that embeds [Verovio](https://www.verovio.org/) — the open-source music notation engraving library used by the MEI community, RISM, and the Music Encoding Initiative — directly into your Android and iOS apps. No server, no WebView, no network. Just native engraving on device.

## Why use it

- **Real engraving, not just rendering** — Verovio lays out music with publication quality (beams, slurs, ties, articulations, lyrics, multi-voice, page breaks).
- **Works offline** — everything runs natively on the device via FFI. No HTTP, no JS bridge.
- **Multiple input formats** — MEI, MusicXML, Humdrum, ABC, Plaine & Easie.
- **SVG output** — vector graphics that scale on any screen, embed in your own widgets, export to PDF, or post-process freely.
- **Isolate-friendly** — `VerovioService.spawn` runs on a worker isolate so rendering never blocks your UI.
- **Drop-in size** — ~7 MB per ABI after `--split-per-abi` on Android.

## Install

```yaml
dependencies:
  verovio_flutter:
    git:
      url: https://github.com/csa8820/verovio_flutter
      ref: v0.1.0
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:verovio_flutter/verovio_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Unpack the Verovio font/data assets once.
  final resourcePath = await VerovioResourceManager.ensureVerovioAssetsReady();

  // 2. Spawn an engraving isolate.
  final service = await VerovioService.spawn(resourcePath: resourcePath);

  // 3. Feed it MEI / MusicXML / ABC / Humdrum.
  service.loadData('''<mei xmlns="http://www.music-encoding.org/ns/mei">
    <music><body><mdiv><score><section/></score></mdiv></body></music>
  </mei>''');

  // 4. Get an SVG string for any page and draw it.
  final svg = service.renderToSvg(1);

  runApp(MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('verovio_flutter')),
      body: SvgPicture.string(svg),
    ),
  ));
}
```

A complete runnable example lives in [`example/`](example).

## Gallery

All images below are produced by Verovio on-device from MEI sources — what you see is what your users will see.

| Vocal score with lyrics | Virtuosic piano writing |
|:---:|:---:|
| ![Mozart — Das Veilchen](doc/images/vocal_with_lyrics.png) | ![Debussy — Golliwogg's Cakewalk](doc/images/piano_solo.png) |
| *Mozart — Das Veilchen, K.476* | *Debussy — Golliwogg's Cakewalk* |

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

See [`doc/api.md`](doc/api.md) for the full `VerovioService` surface (options, page navigation, MIDI export, time-map, etc.).

## Version mapping

| verovio_flutter | Verovio upstream |
|-----------------|------------------|
| 0.1.0           | `version-6.2.1` |

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
