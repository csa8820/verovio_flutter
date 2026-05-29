## 0.2.0

- Added first-class HitMap APIs to `VerovioAsyncService`: `renderPageWithHitMap()` and `parseHitMap()`, so callers can fetch SVG and interaction metadata in one isolate round-trip.
- Added `snapToNearest()` plus R-tree nearest-neighbor search, enabling "click anywhere, snap to the closest note/element" interactions.
- Expanded `VerovioPageCache` to cache both SVG and parsed HitMap data, reducing repeat render/parse overhead.
- Made asset extraction more robust by falling back to the local workspace `assets/verovio_data` directory when running without a Flutter plugin host.
- Exported the HitMap data models and hit-test helpers from the top-level package API for easier consumption.
- Updated documentation and release notes for the 0.2.0 release.

## 0.1.6

- Fix: Replaced the deprecated `AssetManifest.json` lookup in `VerovioResourceManager` with `AssetManifest.loadFromAssetBundle`, restoring asset extraction on Flutter versions that no longer emit the legacy JSON manifest.
- Lowered the minimum SDK constraints to `Dart >=3.0.0` / `Flutter >=3.10.0` to broaden compatibility.
- Downgraded the `flutter_lints` dev dependency to `^3.0.0` to align with the new lower SDK bound.
- Bumped the package version to `0.1.6` and refreshed the install snippets in the docs.

## 0.1.4

- Updated the install examples to `verovio_flutter: ^0.1.4`.
- Updated the documentation to reflect the larger iOS `.xcframework` packaging flow.

## 0.1.3

- Synchronized the package metadata and README version references for the next pub.dev release.

## 0.1.2

- Unified the public API around `VerovioAsyncService` and updated the English/Chinese docs accordingly.
- Added cache and troubleshooting guidance for package users.

## 0.1.1

- Verovio submodule upgraded to `version-6.2.1` (`8d42439dc9231f6c87779287b542febcb3d609b3`).
- Prepared the package for pub.dev publication with bundled Android/iOS native artifacts and assets.

## 0.1.0

- First public release of `verovio_flutter`.
- Supported platforms: Android API 21+ (`arm64-v8a` / `x86_64`) and iOS 13.0+ (`arm64` device / `arm64+x86_64` simulator).
- Verovio submodule: `version-2.7.1-10372-g8100cb396` (`8100cb39604d40102a9c2ce75719136f3fb52a77`).
