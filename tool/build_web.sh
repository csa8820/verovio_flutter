#!/bin/bash
# Complete Web build script: compiles worker and builds Flutter app
# Usage: ./tool/build_web.sh [--clean]

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE_DIR="$PROJECT_ROOT/example"

echo "============================================================"
echo "Verovio Flutter - Web Build Script"
echo "============================================================"
echo ""

# Parse arguments
CLEAN_BUILD=""
if [[ "$1" == "--clean" ]]; then
  CLEAN_BUILD="true"
fi

# Step 1: Compile Dart worker to JavaScript
echo "Step 1: Compiling Web Worker (web/verovio_worker.dart)..."
cd "$PROJECT_ROOT"
dart compile js web/verovio_worker.dart -o web/verovio_worker.dart.js
echo "✓ Worker compiled: web/verovio_worker.dart.js ($(stat -f%z web/verovio_worker.dart.js | numfmt --to=iec 2>/dev/null || ls -lh web/verovio_worker.dart.js | awk '{print $5}'))"
echo ""

# Step 2: Stage the worker and WASM runtime into the app's web/ folder.
# Placing them here makes them available both for `flutter run -d chrome` (dev)
# and `flutter build web`, which copies web/ assets into build/web automatically.
echo "Step 2: Staging Web runtime into example/web/..."
mkdir -p "$EXAMPLE_DIR/web"
cp "$PROJECT_ROOT/web/verovio_worker.dart.js" "$EXAMPLE_DIR/web/verovio_worker.dart.js"
rm -rf "$EXAMPLE_DIR/web/verovio"
cp -R "$PROJECT_ROOT/web/verovio" "$EXAMPLE_DIR/web/"
echo "✓ Worker staged: example/web/verovio_worker.dart.js"
echo "✓ WASM staged:   example/web/verovio/verovio-toolkit-wasm.js"
echo ""

# Step 3: Build Flutter Web app
echo "Step 3: Building Flutter app for Web..."
cd "$EXAMPLE_DIR"
if [[ "$CLEAN_BUILD" == "true" ]]; then
  echo "  (clean build requested)"
  flutter clean
fi
flutter build web
echo "✓ Flutter build complete: example/build/web/"
echo ""

# Verify all resources are in place
echo "Step 4: Verifying resources..."

# Check worker
if [[ -f "$EXAMPLE_DIR/build/web/verovio_worker.dart.js" ]]; then
  size=$(stat -f%z "$EXAMPLE_DIR/build/web/verovio_worker.dart.js" 2>/dev/null || stat -c%s "$EXAMPLE_DIR/build/web/verovio_worker.dart.js" 2>/dev/null || echo "?")
  echo "  ✓ verovio_worker.dart.js ($size bytes)"
else
  echo "  ✗ verovio_worker.dart.js MISSING!"
  exit 1
fi

# Check WASM toolkit (in verovio/ subdirectory)
if [[ -f "$EXAMPLE_DIR/build/web/verovio/verovio-toolkit-wasm.js" ]]; then
  size=$(stat -f%z "$EXAMPLE_DIR/build/web/verovio/verovio-toolkit-wasm.js" 2>/dev/null || stat -c%s "$EXAMPLE_DIR/build/web/verovio/verovio-toolkit-wasm.js" 2>/dev/null || echo "?")
  echo "  ✓ verovio/verovio-toolkit-wasm.js ($size bytes)"
else
  echo "  ✗ verovio/verovio-toolkit-wasm.js MISSING!"
  exit 1
fi
echo ""

echo "============================================================"
echo "Web Build Complete!"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Run 'flutter run -d chrome' to test in Chrome"
echo "  2. Or serve with: python3 -m http.server --directory example/build/web 8000"
echo ""
