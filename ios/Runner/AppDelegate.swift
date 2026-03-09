import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var vpnManager: NETunnelProviderManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "com.yueto.yuelink/vpn", binaryMessenger: controller.binaryMessenger)

        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "startVpn":
                self?.startVpn(result: result)
            case "stopVpn":
                self?.stopVpn(result: result)
            case "requestPermission":
                result(true) // iOS handles permission via system VPN prompt
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func startVpn(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                result(FlutterError(code: "VPN_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()
            self?.vpnManager = manager

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.yueto.yuelink.PacketTunnel"
            proto.serverAddress = "YueLink"
            proto.disconnectOnSleep = false

            manager.protocolConfiguration = proto
            manager.localizedDescription = "YueLink"
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    result(FlutterError(code: "VPN_SAVE_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                manager.loadFromPreferences { error in
                    if let error = error {
                        result(FlutterError(code: "VPN_LOAD_ERROR", message: error.localizedDescription, details: nil))
                        return
                    }

                    do {
                        let session = manager.connection as! NETunnelProviderSession
                        try session.startTunnel()
                        result(true)
                    } catch {
                        result(FlutterError(code: "VPN_START_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func stopVpn(result: @escaping FlutterResult) {
        vpnManager?.connection.stopVPNTunnel()
        result(true)
    }
}
