# Native Library Font Initialization Bug Fix

## Problem Description

The Verovio Flutter demo application crashes with a SIGSEGV (segmentation fault) when attempting to load music score data. The crash occurs in the native library with the following symptoms:

- Error message: "Text font could not be initialized"  
- Warning: "Text font for style (2, 2) is not loaded. Use default"
- Crash location: `vrv_ffi_load_data+172` (null pointer dereference at offset 0x1c)
- BuildId: `b3e6a3f81486d20a55f59df4ed9c17d5d772b30e`

## Root Cause Analysis

The issue occurs in the FFI wrapper function `vrv_ffi_create()` in `/Users/dzh/Documents/trae_projects/verovio_flutter/src/verovio_ffi.cpp`.

### Original (Buggy) Implementation:
```cpp
VrvToolkitHandle vrv_ffi_create(const char* resource_path) {
    try {
        if (resource_path && resource_path[0] != '\0') {
            vrv::SetDefaultResourcePath(resource_path);
        } else {
            vrv::SetDefaultResourcePath("/data");
        }
        return new vrv::Toolkit();  // <-- PROBLEM: Initializes fonts immediately
    } catch (...) {
        return nullptr;
    }
}
```

### The Problem:
1. `vrv::SetDefaultResourcePath()` sets a static thread-local path but doesn't immediately make fonts available
2. The `Toolkit()` constructor (with default `initFont=true`) immediately calls `resources.InitFonts()`
3. At this point, the Resources object may not have properly found or loaded the fonts yet
4. InitFonts() fails with "Text font could not be initialized" but returns false
5. Later, when `LoadData()` is called, it checks `resources.Ok()` which expects more than 1 font loaded
6. Since InitFonts() likely only partially loaded fonts (or failed completely), the check fails but the app still tries to proceed
7. This leads to null pointer dereferences when text fonts are accessed

## Solution

The fix changes the initialization sequence to properly handle resource loading:

### Fixed Implementation:
```cpp
VrvToolkitHandle vrv_ffi_create(const char* resource_path) {
    try {
        vrv::Toolkit* toolkit = new vrv::Toolkit(false);  // Create WITHOUT initializing fonts
        if (!toolkit) return nullptr;

        // Now explicitly set the resource path, which will initialize fonts properly
        std::string path = "/data";
        if (resource_path && resource_path[0] != '\0') {
            path = resource_path;
        }

        // SetResourcePath() calls InitFonts() with proper error checking
        if (!toolkit->SetResourcePath(path)) {
            delete toolkit;
            return nullptr;  // Fail fast if fonts can't be loaded
        }

        return toolkit;
    } catch (...) {
        return nullptr;
    }
}
```

### Why This Works:
1. Creates the Toolkit with `initFont=false` to skip premature initialization
2. Calls `SetResourcePath(path)` which:
   - Sets the path on the Resources object
   - Calls `InitFonts()` with the correctly set path
   - Adds custom fonts if needed
   - Sets options for fonts
   - Returns `false` if ANY required step fails
3. Fails fast if fonts can't be loaded instead of allowing partial initialization
4. When `LoadData()` is later called, the font check `resources.Ok()` will correctly pass or fail based on actual font availability

## File Modified

- **File**: `/Users/dzh/Documents/trae_projects/verovio_flutter/src/verovio_ffi.cpp`
- **Function**: `vrv_ffi_create()` (lines 28-48)
- **Change Type**: Bug fix for resource initialization order

## Build Requirements

To use this fix, the native library must be recompiled from source:

```bash
# From the verovio_flutter directory
flutter clean
rm -rf android/app/build

# Update pubspec.yaml to use local path (already done):
# verovio_flutter:
#   path: ../verovio_flutter

flutter pub get
flutter run -d <device_id>
```

### C++ Build Requirements:
- CMake 3.22.1 or later
- Android NDK 25.1.8937393
- C++20 support (required by Verovio library)

## Status

✅ **Source Code Fix**: Applied to `verovio_ffi.cpp`  
⚠️ **Build Compilation**: Requires resolution of C++20/Android NDK compatibility  
❌ **Runtime Testing**: Pending successful native library compilation

## Next Steps

1. Resolve C++20 compilation issues with Android NDK 25:
   - Option A: Update Android SDK build tools and CMake configuration
   - Option B: Use precompiled binaries from GitHub releases if available

2. Once compiled, the native library should:
   - Properly initialize fonts from the bundled resources
   - Allow music score data to be loaded without crashes
   - Support rendering of MEI, MusicXML, and ABC notation formats

## References

- **Verovio Toolkit**: `third_party/verovio/src/toolkit.cpp` (SetResourcePath method, lines 121-142)
- **Verovio Resources**: `third_party/verovio/src/resources.cpp` (InitFonts method, lines 61-96)
- **FFI Wrapper**: `src/verovio_ffi.cpp` (vrv_ffi_create function, lines 28-48)
