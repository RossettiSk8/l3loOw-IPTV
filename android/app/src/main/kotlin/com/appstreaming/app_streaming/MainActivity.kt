package com.appstreaming.app_streaming

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var screenWakeLock: MethodChannel? = null
    private var otaUpdater: MethodChannel? = null
    private var started = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val installer = OtaInstaller(this)
        otaUpdater = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "l3loow/ota_updater",
        ).apply { setMethodCallHandler(installer::handle) }
        screenWakeLock = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "l3loow/screen_wake_lock",
        ).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "setEnabled") {
                    result.notImplemented()
                } else {
                    setScreenAwake(call.arguments == true && started)
                    result.success(null)
                }
            }
        }
    }

    private fun setScreenAwake(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onStart() {
        super.onStart()
        started = true
    }

    override fun onStop() {
        started = false
        setScreenAwake(false)
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        otaUpdater?.setMethodCallHandler(null)
        otaUpdater = null
        screenWakeLock?.setMethodCallHandler(null)
        screenWakeLock = null
        setScreenAwake(false)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
