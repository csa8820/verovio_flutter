#!/usr/bin/env bash
set -euo pipefail

: "${ANDROID_NDK:?need ANDROID_NDK env, e.g. ~/Library/Android/sdk/ndk/26.1.10909125}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/android/src/main/jniLibs"
VEROVIO_TOOLS="$ROOT/third_party/verovio/tools"

# Default to the ABIs Flutter actually ships. Override e.g. ABIS="arm64-v8a x86_64".
ABIS="${ABIS:-arm64-v8a x86_64}"

NDK_HOST_TAG=""
for tag in darwin-arm64 darwin-x86_64 linux-x86_64; do
  if [ -x "$ANDROID_NDK/toolchains/llvm/prebuilt/$tag/bin/llvm-strip" ]; then
    NDK_HOST_TAG="$tag"
    break
  fi
done
if [ -z "$NDK_HOST_TAG" ]; then
  echo "ERROR: cannot locate llvm-strip under $ANDROID_NDK/toolchains/llvm/prebuilt/{darwin-arm64,darwin-x86_64,linux-x86_64}" >&2
  exit 1
fi
STRIP="$ANDROID_NDK/toolchains/llvm/prebuilt/$NDK_HOST_TAG/bin/llvm-strip"

# Disabled verovio features. These MUST be -D compile macros; src/CMakeLists.txt
# does not translate -DNO_*_SUPPORT cmake vars into preprocessor defines.
FEATURE_DEFINES="-DNO_ABC_SUPPORT -DNO_HUMDRUM_SUPPORT -DNO_DARMS_SUPPORT -DNO_RUNTIME"

# Dead-code stripping + hidden visibility lets the linker drop everything not
# explicitly exported by verovio_ffi.cpp — this is where most of the size win comes from.
SIZE_CFLAGS="-ffunction-sections -fdata-sections -fvisibility=hidden -fvisibility-inlines-hidden -flto=thin"
SIZE_LDFLAGS="-Wl,--gc-sections -Wl,--icf=all -Wl,-z,max-page-size=0x4000 -flto=thin -static-libstdc++ -Wl,--exclude-libs,ALL"

mkdir -p "$ROOT/third_party/verovio/include/vrv"
(cd "$VEROVIO_TOOLS" && bash ./get_git_commit.sh || true)

rm -rf "$OUT"
mkdir -p "$OUT"

for ABI in $ABIS; do
  BUILD="$ROOT/build/android-$ABI"
  rm -rf "$BUILD"
  mkdir -p "$BUILD"

  cmake -S "$ROOT/src" -B "$BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM=android-21 \
    -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_AS_ANDROID_LIBRARY=ON \
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG $FEATURE_DEFINES $SIZE_CFLAGS" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG $FEATURE_DEFINES $SIZE_CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS_RELEASE="$SIZE_LDFLAGS"

  # Parallelism: honor BUILD_JOBS env (CI caps it to avoid OOM on small runners),
  # otherwise auto-detect cross-platform (Linux: getconf, macOS: sysctl), fallback 2.
  JOBS="${BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)}"
  cmake --build "$BUILD" -j"$JOBS"

  mkdir -p "$OUT/$ABI"
  cp "$BUILD/libverovio_flutter.so" "$OUT/$ABI/"
  "$STRIP" --strip-all "$OUT/$ABI/libverovio_flutter.so"

  printf '  %-12s %s\n' "$ABI" "$(du -h "$OUT/$ABI/libverovio_flutter.so" | cut -f1)"
done

echo "android .so built for: $ABIS"
