package com.yueto.yuelink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor

class YueLinkVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.yueto.yuelink.action.START"
        const val ACTION_STOP = "com.yueto.yuelink.action.STOP"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "yuelink_vpn"
    }

    private var tunFd: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startTunnel()
            ACTION_STOP -> stopTunnel()
        }
        return START_STICKY
    }

    private fun startTunnel() {
        if (tunFd != null) return

        // Create TUN interface
        val builder = Builder()
            .setSession("YueLink")
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .addDnsServer("223.5.5.5")
            .addDnsServer("8.8.8.8")
            .setMtu(9000)
            .setBlocking(false)

        tunFd = builder.establish()

        if (tunFd != null) {
            val fd = tunFd!!.fd
            // TODO: Pass fd to Go core via JNI
            // NativeCore.setTunFd(fd)

            startForeground(NOTIFICATION_ID, createNotification())
        }
    }

    private fun stopTunnel() {
        // TODO: Tell Go core to stop using the TUN fd
        // NativeCore.stopTun()

        tunFd?.close()
        tunFd = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopTunnel()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "YueLink VPN",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "YueLink VPN service status"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("YueLink")
            .setContentText("VPN 已连接")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
