package com.yueto.yuelink

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.VpnService
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val VPN_CHANNEL = "com.yueto.yuelink/vpn"
        private const val VPN_REQUEST_CODE = 1001
    }

    private var vpnPermissionResult: MethodChannel.Result? = null
    private var vpnStartResult: MethodChannel.Result? = null

    private var vpnService: YueLinkVpnService? = null
    private var serviceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            vpnService = (service as YueLinkVpnService.LocalBinder).getService()
            serviceBound = true
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            vpnService = null
            serviceBound = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestVpnPermission(result)
                    "startVpn" -> {
                        val mixedPort = call.argument<Int>("mixedPort") ?: 7890
                        startVpnService(mixedPort, result)
                    }
                    "stopVpn" -> stopVpnService(result)
                    "getTunFd" -> result.success(vpnService?.getTunFd() ?: -1)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            vpnPermissionResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            result.success(true)
        }
    }

    private fun startVpnService(mixedPort: Int, result: MethodChannel.Result) {
        // Check / request VPN permission first
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            vpnPermissionResult = null
            vpnStartResult = result
            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
            return
        }

        doStartVpnService(mixedPort, result)
    }

    private fun doStartVpnService(mixedPort: Int, result: MethodChannel.Result) {
        val serviceIntent = Intent(this, YueLinkVpnService::class.java).apply {
            action = YueLinkVpnService.ACTION_START
            putExtra(YueLinkVpnService.EXTRA_MIXED_PORT, mixedPort)
        }
        startForegroundService(serviceIntent)

        // Bind to receive the TUN fd via callback
        val bindIntent = Intent(this, YueLinkVpnService::class.java)
        bindService(bindIntent, serviceConnection, Context.BIND_AUTO_CREATE)

        // Wait for the service to establish the TUN and deliver the fd
        // We set the callback — the service calls it once the fd is ready
        val checkFd = Runnable {
            // Service may already be running; poll the fd
        }

        // Use a short delayed mechanism via Handler to poll once bound
        android.os.Handler(mainLooper).postDelayed({
            val bound = vpnService
            if (bound != null) {
                bound.onTunReady = { fd ->
                    result.success(fd)
                }
                // If already running, trigger immediately
                val currentFd = bound.getTunFd()
                if (currentFd != -1) {
                    bound.onTunReady = null
                    result.success(currentFd)
                }
            } else {
                // Service not yet bound — return -1, Flutter will retry
                result.success(-1)
            }
        }, 500)
    }

    private fun stopVpnService(result: MethodChannel.Result) {
        val serviceIntent = Intent(this, YueLinkVpnService::class.java).apply {
            action = YueLinkVpnService.ACTION_STOP
        }
        startService(serviceIntent)
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
            vpnService = null
        }
        result.success(true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val granted = resultCode == Activity.RESULT_OK
            if (vpnPermissionResult != null) {
                vpnPermissionResult?.success(granted)
                vpnPermissionResult = null
            } else if (vpnStartResult != null) {
                val pendingResult = vpnStartResult!!
                vpnStartResult = null
                if (granted) {
                    doStartVpnService(7890, pendingResult)
                } else {
                    pendingResult.success(-1)
                }
            }
        }
    }

    override fun onDestroy() {
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
        super.onDestroy()
    }
}
