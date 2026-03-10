package com.yueto.yuelink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor

class YueLinkVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.yueto.yuelink.action.START"
        const val ACTION_STOP = "com.yueto.yuelink.action.STOP"

        // Extra key: mixed-port value passed from Flutter when starting
        const val EXTRA_MIXED_PORT = "mixed_port"

        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "yuelink_vpn"
    }

    inner class LocalBinder : Binder() {
        fun getService() = this@YueLinkVpnService
    }

    private val binder = LocalBinder()
    private var tunFd: ParcelFileDescriptor? = null

    // Callback invoked once TUN is established, delivers the raw fd integer to MainActivity
    var onTunReady: ((Int) -> Unit)? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val mixedPort = intent.getIntExtra(EXTRA_MIXED_PORT, 7890)
                startTunnel(mixedPort)
            }
            ACTION_STOP -> stopTunnel()
        }
        return START_STICKY
    }

    private fun startTunnel(mixedPort: Int) {
        if (tunFd != null) {
            // Already running — deliver the existing fd
            onTunReady?.invoke(tunFd!!.fd)
            return
        }

        val builder = Builder()
            .setSession("YueLink")
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .addDnsServer("223.5.5.5")
            .addDnsServer("8.8.8.8")
            .setMtu(9000)
            .setBlocking(false)
            // Allow the app itself to bypass the VPN (so the mihomo process
            // can reach the internet directly without a routing loop)
            .addDisallowedApplication(packageName)

        tunFd = builder.establish()

        val fd = tunFd?.fd
        if (fd != null) {
            startForeground(NOTIFICATION_ID, createNotification())
            // Deliver fd to Flutter layer so it can be injected into config YAML
            onTunReady?.invoke(fd)
        }
    }

    private fun stopTunnel() {
        tunFd?.close()
        tunFd = null
        onTunReady = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** The raw fd of the active TUN interface, or -1 if not running. */
    fun getTunFd(): Int = tunFd?.fd ?: -1

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
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
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
