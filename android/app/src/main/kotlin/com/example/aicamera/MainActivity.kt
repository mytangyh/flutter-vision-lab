package com.example.aicamera

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aicamera/platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPlatformInfo" -> result.success(
                    mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "androidSdk" to Build.VERSION.SDK_INT,
                        "abi" to Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
                    ),
                )
                "shareJson" -> {
                    val json = call.argument<String>("json").orEmpty()
                    val sendIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/json"
                        putExtra(Intent.EXTRA_SUBJECT, "AICAMERA benchmark")
                        putExtra(Intent.EXTRA_TEXT, json)
                    }
                    startActivity(Intent.createChooser(sendIntent, "分享基准报告"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
