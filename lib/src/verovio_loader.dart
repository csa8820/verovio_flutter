// Platform-specific loader for the Verovio native library.
//
// Conditional import:
// - IO 平台（Android/iOS）：使用 verovio_loader_io.dart，返回 DynamicLibrary
// - Web 平台：使用 verovio_loader_web.dart，抛出 UnsupportedError
//
// 注意：入口文件通过 export 暴露 loadVerovioLibrary 函数，
// 避免在签名中直接使用 dart:ffi 类型（Web 编译时不可用）。
export 'verovio_loader_io.dart'
    if (dart.library.js_interop) 'verovio_loader_web.dart';
