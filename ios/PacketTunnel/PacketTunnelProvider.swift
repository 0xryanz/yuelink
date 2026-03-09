import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        // IPv4 configuration
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // DNS
        settings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "8.8.8.8"])

        // MTU
        settings.mtu = 9000

        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                completionHandler(error)
                return
            }

            // TODO: Start mihomo Go core (linked as static library)
            // let configPath = self.appGroupConfigPath()
            // InitCore(configPath)
            // StartCore(configYaml)

            completionHandler(nil)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        // TODO: Stop mihomo Go core
        // StopCore()

        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // IPC between main app and tunnel extension
        // Used for sending config updates, getting status, etc.
        completionHandler?(nil)
    }

    /// Get the shared App Group container path for config files.
    private func appGroupConfigPath() -> String {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.yueto.yuelink"
        )
        return container?.appendingPathComponent("yuelink.yaml").path ?? ""
    }
}
