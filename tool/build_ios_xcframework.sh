#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
XCFRAMEWORK_OUT="$ROOT/ios/Frameworks/VerovioFFI.xcframework"
WORK_ROOT="$ROOT/build/ios"
PROJECT_COPY_ROOT="$WORK_ROOT/verovio_xcodebuild"
PROJECT_COPY="$PROJECT_COPY_ROOT/Verovio.xcodeproj"
PROJECT_PBXPROJ="$PROJECT_COPY/project.pbxproj"
PROJECT_SRC_RESOURCES="$PROJECT_COPY_ROOT/src/resources.cpp"

VEROVIO_ROOT="$ROOT/third_party/verovio"
INCLUDE_PATHS=(
  "$ROOT/src"
  "$VEROVIO_ROOT/include"
  "$VEROVIO_ROOT/include/vrv"
  "$VEROVIO_ROOT/include/pugi"
  "$VEROVIO_ROOT/include/midi"
  "$VEROVIO_ROOT/include/crc"
  "$VEROVIO_ROOT/include/hum"
  "$VEROVIO_ROOT/include/json"
  "$VEROVIO_ROOT/include/tuning-library"
  "$VEROVIO_ROOT/include/zip"
  "$VEROVIO_ROOT/libmei/dist"
  "$VEROVIO_ROOT/libmei/addons"
)
HEADER_SEARCH_PATHS="$(printf '%s ' "${INCLUDE_PATHS[@]}")"
HEADER_SEARCH_PATHS="${HEADER_SEARCH_PATHS% }"

DEVICE_BUILD_ROOT="$WORK_ROOT/device-arm64"
SIM_BUILD_ROOT="$WORK_ROOT/sim"
IOS_ARCHIVE="$WORK_ROOT/VerovioFramework-iOS.xcarchive"
SIM_ARCHIVE="$WORK_ROOT/VerovioFramework-Sim.xcarchive"

cleanup() {
  if [[ -d "$WORK_ROOT" ]]; then
    rm -rf "$WORK_ROOT"
  fi
}

trap cleanup EXIT

if [[ ! -d "$VEROVIO_ROOT" ]]; then
  echo "Missing Verovio submodule: $VEROVIO_ROOT" >&2
  exit 1
fi

rm -rf "$XCFRAMEWORK_OUT" "$WORK_ROOT"
mkdir -p "$(dirname "$XCFRAMEWORK_OUT")" "$WORK_ROOT"
rsync -a --exclude '.git' --exclude 'build' "$VEROVIO_ROOT"/ "$PROJECT_COPY_ROOT"/

python3 - "$PROJECT_PBXPROJ" "$PROJECT_COPY_ROOT" <<'PY'
from __future__ import annotations

import pathlib
import re
import secrets
import sys

pbxproj_path = pathlib.Path(sys.argv[1])
project_copy_root = sys.argv[2]
text = pbxproj_path.read_text()

text = text.replace('projectDirPath = "";', f'projectDirPath = "{project_copy_root}";')

def new_id() -> str:
    return secrets.token_hex(12).upper()

build_file_id = new_id()
file_ref_id = new_id()
framework_build_file_id = new_id()

build_file_entry = (
    f"\t\t{build_file_id} /* verovio_ffi.cpp in Sources */ = "
    f"{{isa = PBXBuildFile; fileRef = {file_ref_id} /* verovio_ffi.cpp */; }};\n"
)
framework_build_file_entry = (
    f"\t\t{framework_build_file_id} /* verovio_ffi.cpp in Sources */ = "
    f"{{isa = PBXBuildFile; fileRef = {file_ref_id} /* verovio_ffi.cpp */; }};\n"
)
file_ref_entry = (
    f"\t\t{file_ref_id} /* verovio_ffi.cpp */ = "
    f"{{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.cpp.cpp; "
    f"name = verovio_ffi.cpp; path = src/verovio_ffi.cpp; sourceTree = \"<group>\"; }};\n"
)

if 'verovio_ffi.cpp in Sources' not in text:
    text = text.replace(
        '\t\t4DD11DC42240E78B00A405D8 /* c_wrapper.cpp in Sources */ = {isa = PBXBuildFile; fileRef = 4DD11DC22240E78B00A405D8 /* c_wrapper.cpp */; };\n',
        '\t\t4DD11DC42240E78B00A405D8 /* c_wrapper.cpp in Sources */ = {isa = PBXBuildFile; fileRef = 4DD11DC22240E78B00A405D8 /* c_wrapper.cpp */; };\n'
        + build_file_entry,
    )
    text = text.replace(
        '\t\t4DD11DC22240E78B00A405D8 /* c_wrapper.cpp */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.cpp.cpp; name = c_wrapper.cpp; path = tools/c_wrapper.cpp; sourceTree = "<group>"; };\n',
        '\t\t4DD11DC22240E78B00A405D8 /* c_wrapper.cpp */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.cpp.cpp; name = c_wrapper.cpp; path = tools/c_wrapper.cpp; sourceTree = "<group>"; };\n'
        + file_ref_entry,
    )

sources_start = text.find('8F086F4918853CA90037FD8E /* Sources */ = {')
if sources_start == -1:
    raise SystemExit('Could not locate libverovio sources build phase')
files_anchor = 'files = (\n'
files_start = text.find(files_anchor, sources_start)
if files_start == -1:
    raise SystemExit('Could not locate libverovio sources list')
files_start += len(files_anchor)
files_end = text.find('\n\t\t\t\t);\n', files_start)
if files_end == -1:
    raise SystemExit('Could not locate end of libverovio sources list')
files_block = text[files_start:files_end]
if 'verovio_ffi.cpp in Sources' not in files_block:
    files_block = files_block + f'\t\t\t\t\t{build_file_id} /* verovio_ffi.cpp in Sources */,\n'
    text = text[:files_start] + files_block + text[files_end:]

framework_sources_start = text.find('BB4C4A4E22A930A3001F6AF0 /* Sources */ = {')
if framework_sources_start == -1:
    raise SystemExit('Could not locate VerovioFramework sources build phase')
framework_files_start = text.find(files_anchor, framework_sources_start)
if framework_files_start == -1:
    raise SystemExit('Could not locate VerovioFramework sources list')
framework_files_start += len(files_anchor)
framework_files_end = text.find('\n\t\t\t\t);\n', framework_files_start)
if framework_files_end == -1:
    raise SystemExit('Could not locate end of VerovioFramework sources list')
framework_files_block = text[framework_files_start:framework_files_end]
if 'verovio_ffi.cpp in Sources' not in framework_files_block:
    framework_files_block = framework_files_block + f'\t\t\t\t\t{framework_build_file_id} /* verovio_ffi.cpp in Sources */,\n'
    text = text[:framework_files_start] + framework_files_block + text[framework_files_end:]

pbxproj_path.write_text(text)
PY

python3 - "$PROJECT_SRC_RESOURCES" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
if '#include <dirent.h>' not in text:
    text = text.replace('#include <fstream>\n', '#include <fstream>\n#include <dirent.h>\n')
pattern = re.compile(r"bool Resources::LoadAll\(\)\n\{\n.*?\n\}\n\nvoid Resources::SetFallbackFont", re.S)
replacement = """bool Resources::LoadAll()
{
    std::string path = Resources::GetPath() + "/";
    auto *dir = opendir(path.c_str());
    if (dir == nullptr) {
        return false;
    }
    auto *entry = readdir(dir);
    while (entry != nullptr) {
        const std::string filename(entry->d_name);
        if (filename == "." || filename == "..") {
            continue;
        }
        if (filename.size() > 4 && filename.rfind(".xml") == filename.size() - 4) {
            const std::string fontName = filename.substr(0, filename.size() - 4);
            if (!this->IsFontLoaded(fontName) && !this->LoadFont(fontName)) {
                closedir(dir);
                return false;
            }
        }
        entry = readdir(dir);
    }
    closedir(dir);
    return true;
}

void Resources::SetFallbackFont"""
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit('Could not locate LoadAll() body in build copy resources.cpp')
pattern = re.compile(r"std::string Resources::GetCustomFontname\(\s*const std::string &filename, const ZipFileReader &zipFile\s*\)\n\{.*?\n\}\n\nvoid Resources::SelectTextFont", re.S)
replacement = """std::string Resources::GetCustomFontname(
    const std::string &filename, const ZipFileReader &zipFile)
{
#ifdef __EMSCRIPTEN__
    // Extracts the font name from the bounding box XML file
    // For example, OneGlyph/OneGlyph.xml
    for (auto &s : zipFile.GetFileList()) {
        const auto slash = s.find_last_of('/');
        const std::string basename = (slash == std::string::npos) ? s : s.substr(slash + 1);
        const auto dot = basename.rfind('.');
        if (dot != std::string::npos && basename.substr(dot) == ".xml") {
            return basename.substr(0, dot);
        }
    }
    LogWarning("The font name could not be extracted from the archive XML file");
    return "";
#else
    const auto slash = filename.find_last_of('/');
    const std::string basename = (slash == std::string::npos) ? filename : filename.substr(slash + 1);
    const auto dot = basename.rfind('.');
    return (dot != std::string::npos) ? basename.substr(0, dot) : basename;
#endif
}

void Resources::SelectTextFont"""
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit('Could not locate GetCustomFontname() body in build copy resources.cpp')
path.write_text(text)
PY

# Disabled verovio features. Injected as preprocessor macros so that the
# `#ifdef NO_*_SUPPORT` guards in verovio sources actually fire.
FEATURE_DEFINES="NO_ABC_SUPPORT=1 NO_HUMDRUM_SUPPORT=1 NO_DARMS_SUPPORT=1 NO_RUNTIME=1"

echo "Checking Xcode first-launch status..."
"$XCODEBUILD" -checkFirstLaunchStatus

archive_framework() {
  local destination="$1"
  local archive_path="$2"
  rm -rf "$archive_path"
  "$XCODEBUILD" \
    -project "$PROJECT_COPY" \
    -scheme VerovioFramework \
    -configuration Release \
    -destination "$destination" \
    -archivePath "$archive_path" \
    -derivedDataPath "$SIM_BUILD_ROOT/DerivedData-$(basename "$archive_path")" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    IPHONEOS_DEPLOYMENT_TARGET=12.0 \
    CLANG_CXX_LANGUAGE_STANDARD=c++20 \
    CLANG_CXX_LIBRARY=libc++ \
    HEADER_SEARCH_PATHS="$HEADER_SEARCH_PATHS" \
    GCC_PREPROCESSOR_DEFINITIONS="\$(inherited) $FEATURE_DEFINES" \
    GCC_OPTIMIZATION_LEVEL=z \
    LLVM_LTO=YES_THIN \
    GCC_SYMBOLS_PRIVATE_EXTERN=YES \
    GCC_INLINES_ARE_PRIVATE_EXTERN=YES \
    DEAD_CODE_STRIPPING=YES \
    GCC_FUNCTION_SECTIONS=YES \
    GCC_DATA_SECTIONS=YES \
    GCC_NO_COMMON_BLOCKS=YES \
    GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
    DEBUG_INFORMATION_FORMAT=dwarf \
    DEPLOYMENT_POSTPROCESSING=YES \
    STRIP_INSTALLED_PRODUCT=NO \
    STRIP_STYLE=non-global \
    COPY_PHASE_STRIP=NO \
    ENABLE_BITCODE=NO \
    ENABLE_NS_ASSERTIONS=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    CODE_SIGN_STYLE=Manual \
    archive
}

echo "Archiving device framework..."
archive_framework 'generic/platform=iOS' "$IOS_ARCHIVE"

echo "Archiving simulator framework..."
archive_framework 'generic/platform=iOS Simulator' "$SIM_ARCHIVE"

echo "Creating xcframework..."
"$XCODEBUILD" -create-xcframework \
  -framework "$IOS_ARCHIVE/Products/Library/Frameworks/VerovioFramework.framework" \
  -framework "$SIM_ARCHIVE/Products/Library/Frameworks/VerovioFramework.framework" \
  -output "$XCFRAMEWORK_OUT"

# Strip the bundled `data/` from each framework slice.
# These SMuFL font resources are shipped to the app via `assets/verovio_data/`
# (see VerovioResourceManager) and unpacked at runtime to
# getApplicationSupportDirectory(); the copy inside the framework would just
# duplicate ~11MB per slice into the final IPA.
for data_dir in "$XCFRAMEWORK_OUT"/*/VerovioFramework.framework/data; do
  [[ -d "$data_dir" ]] || continue
  rm -rf "$data_dir"
done

echo "Done: $XCFRAMEWORK_OUT"
for slice in "$XCFRAMEWORK_OUT"/*/VerovioFramework.framework/VerovioFramework; do
  [[ -f "$slice" ]] || continue
  printf '  %-40s %s\n' "$(basename "$(dirname "$(dirname "$slice")")")" "$(du -h "$slice" | cut -f1)"
done
