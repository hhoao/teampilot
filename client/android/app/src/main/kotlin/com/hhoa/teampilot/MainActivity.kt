package com.hhoa.teampilot

import android.util.Log
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.hhoa.teampilot/background",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAttentionKeeperEnabled" -> {
                    attentionKeeperEnabled =
                        call.argument<Boolean>("enabled") ?: false
                    Log.i(
                        "AttentionKeeper",
                        "Dart preference enabled=$attentionKeeperEnabled",
                    )
                    if (!attentionKeeperEnabled) {
                        AttentionKeepAliveService.stop(this)
                    }
                    result.success(true)
                }
                "isAttentionKeeperRunning" ->
                    result.success(AttentionKeepAliveService.running)
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (attentionKeeperEnabled) {
            AttentionKeepAliveService.start(this)
        }
    }

    override fun onPause() {
        super.onPause()
        if (attentionKeeperEnabled) {
            AttentionKeepAliveService.start(this)
        }
    }

    override fun onResume() {
        super.onResume()
        AttentionKeepAliveService.stop(this)
    }

    override fun onDestroy() {
        if (isFinishing) {
            AttentionKeepAliveService.stop(this)
        }
        super.onDestroy()
    }

    companion object {
        // Activity recreation must not clear the preference while the Flutter
        // engine keeps running. The Dart side re-syncs after a full restart.
        @Volatile
        private var attentionKeeperEnabled = false
    }
}
