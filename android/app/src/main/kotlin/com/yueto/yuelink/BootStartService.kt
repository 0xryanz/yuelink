package com.yueto.yuelink

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Short-lived foreground service that relays the boot event to MainActivity
 * on Android 10+ where background activity launches are restricted.
 *
 * On Android 12+ (API 31+), background activity launches are blocked even from
 * foreground services. We use a full-screen intent as the launch mechanism —
 * the system treats it as a high-priority notification that can launch an
 * Activity from the background.
 */
class BootStartService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("auto_connect", true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: use full-screen intent to launch from background
            showFullScreenNotification(launch)
        } else {
            // Android 10-11: foreground service can launch activity directly
            showForegroundNotification(launch)
            try {
                startActivity(launch)
            } catch (e: Exception) {
                android.util.Log.w("YueLinkBoot", "startActivity failed: ${e.message}")
            }
        }

        // Stop self after a short delay to let the notification/activity launch
        android.os.Handler(mainLooper).postDelayed({ stopSelf() }, 2000)
        return START_NOT_STICKY
    }

    private fun showFullScreenNotification(launch: Intent) {
        val channelId = "yuelink_boot"
        val channel = NotificationChannel(
            channelId,
            "YueLink Auto-connect",
            // IMPORTANCE_HIGH is required for full-screen intent to work
            NotificationManager.IMPORTANCE_HIGH
        ).apply { description = "Auto-connect after boot" }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)

        val pendingIntent = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("YueLink")
            .setContentText("Starting after boot…")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()
        startForeground(2, notification)
    }

    private fun showForegroundNotification(launch: Intent) {
        val channelId = "yuelink_boot"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "YueLink Auto-connect",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("YueLink")
            .setContentText("Starting after boot…")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .build()
        startForeground(2, notification)
    }
}
