package com.csa8820.verovio_flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin

class VerovioFlutterPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // No-op: native libraries are prebuilt and loaded directly by FFI.
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // No-op.
    }
}
