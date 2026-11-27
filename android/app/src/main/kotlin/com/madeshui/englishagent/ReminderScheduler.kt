package com.madeshui.englishagent

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.util.Calendar

/**
 * 每日提醒：AlarmManager 的 inexactRepeating + 本地通知。
 * 不依赖服务器；不申请精确闹钟权限，省电策略下可能晚几分钟。
 */
object ReminderScheduler {
    const val CHANNEL_ID = "daily_reminder"
    const val PREFS = "reminder_prefs"
    const val KEY_ON = "enabled"
    const val KEY_HOUR = "hour"
    const val KEY_MINUTE = "minute"
    const val REQ = 1001
    private const val ALARM_REQ = 2001

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(
                CHANNEL_ID,
                "每日提醒",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            ch.description = "到点提醒回来背单词"
            mgr.createNotificationChannel(ch)
        }
    }

    fun hasPermission(ctx: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(
                ctx, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else true
    }

    fun schedule(ctx: Context, hour: Int, minute: Int) {
        ensureChannel(ctx)
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ON, true)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .apply()

        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_MONTH, 1)
            }
        }

        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // 用一次性 setAndAllowWhileIdle，触发后再排下一天。
        // setInexactRepeating 在部分国产 ROM 上窗口会被拉到十几小时。
        am.cancel(pending(ctx))
        am.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            cal.timeInMillis,
            pending(ctx)
        )
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx))
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ON, false).apply()
    }

    fun isEnabled(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ON, false)

    fun savedHour(ctx: Context): Int =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_HOUR, 20)

    fun savedMinute(ctx: Context): Int =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_MINUTE, 0)

    private fun pending(ctx: Context): PendingIntent {
        val intent = Intent(ctx, ReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            ctx,
            ALARM_REQ,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun show(ctx: Context) {
        ensureChannel(ctx)
        if (!hasPermission(ctx)) return

        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val pi = PendingIntent.getActivity(
            ctx,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val n = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("该背单词了")
            .setContentText("今天的词还在等你，十分钟就能过一遍")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        NotificationManagerCompat.from(ctx).notify(REQ, n)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.show(context)
        // 一次性闹钟：响过之后立刻排明天同一时间
        if (ReminderScheduler.isEnabled(context)) {
            ReminderScheduler.schedule(
                context,
                ReminderScheduler.savedHour(context),
                ReminderScheduler.savedMinute(context)
            )
        }
    }
}

class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (ReminderScheduler.isEnabled(context)) {
            ReminderScheduler.schedule(
                context,
                ReminderScheduler.savedHour(context),
                ReminderScheduler.savedMinute(context)
            )
        }
    }
}
