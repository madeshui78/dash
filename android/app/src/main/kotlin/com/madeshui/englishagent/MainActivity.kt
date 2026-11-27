package com.madeshui.englishagent

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "app.reminder"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        openFromIntent(intent)

        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val hour = call.argument<Int>("hour") ?: 20
                        val minute = call.argument<Int>("minute") ?: 0
                        ReminderScheduler.schedule(this, hour, minute)
                        result.success(true)
                    }
                    "cancel" -> {
                        ReminderScheduler.cancel(this)
                        result.success(true)
                    }
                    "isEnabled" -> result.success(ReminderScheduler.isEnabled(this))
                    "permission" -> result.success(ReminderScheduler.hasPermission(this))
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            !ReminderScheduler.hasPermission(this)
                        ) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                9001
                            )
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openFromIntent(intent)
    }

    /// 从通知点进来时带 open=study，让 Flutter 切到单词本
    private fun openFromIntent(intent: Intent?) {
        if (intent?.getStringExtra("open") != "study") return
        intent.removeExtra("open")
        Handler(Looper.getMainLooper()).postDelayed({
            channel?.invokeMethod("openStudy", null)
        }, 700)
    }
}
