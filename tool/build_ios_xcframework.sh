#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ios/VerovioFFI.xcodeproj"
SCHEME="VerovioFFI"
OUT="$ROOT/ios/Frameworks"
BUILD="$ROOT/build/ios-xcframework"
IOS_ARCHIVE="$BUILD/VerovioFFI-iOS.xcarchive"
SIM_ARCHIVE="$BUILD/VerovioFFI-Sim.xcarchive"

mkdir -p "$OUT" "$BUILD"
rm -rf "$IOS_ARCHIVE" "$SIM_ARCHIVE" "$OUT/VerovioFFI.xcframework"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$IOS_ARCHIVE" \
  -derivedDataPath "$BUILD/DerivedData-iOS" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  archive

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -archivePath "$SIM_ARCHIVE" \
  -derivedDataPath "$BUILD/DerivedData-Sim" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  archive

xcodebuild -create-xcframework \
  -framework "$IOS_ARCHIVE/Products/Library/Frameworks/VerovioFFI.framework" \
  -framework "$SIM_ARCHIVE/Products/Library/Frameworks/VerovioFFI.framework" \
  -output "$OUT/VerovioFFI.xcframework"
