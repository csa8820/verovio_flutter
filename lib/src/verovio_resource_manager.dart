// Platform-specific manager for Verovio assets.
//
// Conditional import:
// - IO 平台（Android/iOS）：使用 verovio_resource_manager_io.dart，
//   从 asset 拷贝资源到文件系统
// - Web 平台：使用 verovio_resource_manager_web.dart，资源内嵌 WASM，no-op
//
// 注意：入口文件通过 export 暴露 VerovioResourceManager 类，
// 避免直接引入 dart:io 和 path_provider（Web 编译时不可用）。
export 'verovio_resource_manager_io.dart'
    if (dart.library.js_interop) 'verovio_resource_manager_web.dart';
