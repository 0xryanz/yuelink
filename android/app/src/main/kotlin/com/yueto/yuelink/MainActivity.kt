package com.yueto.yuelink

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val VPN_CHANNEL = "com.yueto.yuelink/vpn"
        private const val VPN_REQUEST_CODE = 1001
    }

    private var vpnPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestVpnPermission(result)
                    "startVpn" -> startVpnService(result)
                    "stopVpn" -> stopVpnService(result)
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
            // Permission already granted
            result.success(true)
        }
    }

    private fun startVpnService(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            // Need permission first
            vpnPermissionResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
            return
        }
        val serviceIntent = Intent(this, YueLinkVpnService::class.java)
        serviceIntent.action = YueLinkVpnService.ACTION_START
        startForegroundService(serviceIntent)
        result.success(true)
    }

    private fun stopVpnService(result: MethodChannel.Result) {
        val serviceIntent = Intent(this, YueLinkVpnService::class.java)
        serviceIntent.action = YueLinkVpnService.ACTION_STOP
        startService(serviceIntent)
        result.success(true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val granted = resultCode == Activity.RESULT_OK
            vpnPermissionResult?.success(granted)
            vpnPermissionResult = null
        }
    }
}
