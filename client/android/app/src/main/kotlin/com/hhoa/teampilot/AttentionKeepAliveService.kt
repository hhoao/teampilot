package com.hhoa.teampilot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Keeps the Flutter process alive while TeamPilot is backgrounded so the
 * existing attention connection can deliver session-idle notifications.
 *
 * The service is deliberately only a process keeper: it does not start a
 * second Flutter engine or open its own connection. If Android kills the app,
 * the service is not restarted (START_NOT_STICKY), so a later notification
 * would need a system push channel.
 */
class AttentionKeepAliveService : Service() {
    override fun onCreate() {
        super.onCreate()
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        Log.i(TAG, "foreground attention keeper started")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
        }
        // The Dart engine owns the connection. Restarting this service without
        // that engine would only leave a misleading ongoing notification.
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        Log.i(TAG, "foreground attention keeper stopped")
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.background_attention_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.background_attention_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_teampilot)
            .setContentTitle(getString(R.string.background_attention_title))
            .setContentText(getString(R.string.background_attention_text))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
            )
            .build()
    }

    companion object {
        private const val TAG = "AttentionKeeper"
        private const val CHANNEL_ID = "teampilot_background_attention"
        private const val NOTIFICATION_ID = 41001
        private const val ACTION_STOP =
            "com.hhoa.teampilot.action.STOP_ATTENTION_KEEPER"

        @Volatile
        var running: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, AttentionKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                // Android 12+ can reject a foreground-service start if the
                // activity is already considered background. There is no safe
                // fallback without a user-visible prompt, so keep the app
                // usable and rely on the next onPause transition.
                Log.w(TAG, "start failed", error)
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(
                    Intent(context, AttentionKeepAliveService::class.java),
                )
            } catch (error: Exception) {
                Log.w(TAG, "stop failed", error)
            }
        }
    }
}
