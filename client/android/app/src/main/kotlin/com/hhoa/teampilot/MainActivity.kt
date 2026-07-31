package com.hhoa.teampilot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.hhoa.teampilot/packages",
        ).setMethodCallHandler { call, result ->
            if (call.method == "isPackageInstalled") {
                val packageName = call.argument<String>("packageName") ?: ""
                try {
                    packageManager.getPackageInfo(packageName, 0)
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
