/// Web 平台 stub：Verovio 原生库加载不适用（Web 使用 WASM）。
///
/// 此函数在 Web 平台上总是抛出 [UnsupportedError]。
/// 返回类型为 dynamic，以避免 Web 编译时接触 dart:ffi 类型。
dynamic loadVerovioLibrary() {
  throw UnsupportedError(
    'loadVerovioLibrary is not supported on Web platform; '
    'Web uses WASM via Web Worker instead',
  );
}
