package com.madeshui.englishagent

import android.Manifest
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "app.reminder"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
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
}
