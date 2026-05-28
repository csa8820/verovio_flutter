# verovio_flutter_example

This folder contains the Flutter example app for `verovio_flutter`.

## What it shows

- How to add `verovio_flutter` to a Flutter app
- How to prepare Verovio assets with `VerovioResourceManager`
- How to spawn a `VerovioService` or `VerovioAsyncService`
- How to render score data to SVG and show it in the UI

## Running the example

From the repository root:

```bash
cd example
flutter run
```

The example package includes a small `assets/testdata/` bundle with sample MEI and MusicXML files you can load during local experimentation.

## Notes

- The example app is intentionally lightweight and may be adapted to your own playback / rendering workflow.
- If you only need the API reference, see [`../doc/api.md`](../doc/api.md).
