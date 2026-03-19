import 'dart:ui';

/// Protocol-aware color for node type badges.
/// Returns null for unknown/generic protocols (falls back to default badge style).
Color? protocolColor(String type) {
  switch (type.toLowerCase()) {
    case 'hysteria2':
    case 'hysteria':
      return const Color(0xFF8B5CF6); // Violet — QUIC/UDP protocol
    case 'anytls':
      return const Color(0xFF06B6D4); // Cyan — TLS multiplexed
    case 'vless':
      return const Color(0xFF3B82F6); // Blue
    case 'vmess':
      return const Color(0xFF6366F1); // Indigo
    case 'trojan':
      return const Color(0xFFF59E0B); // Amber
    case 'ss':
    case 'shadowsocks':
      return const Color(0xFF10B981); // Emerald
    case 'tuic':
      return const Color(0xFFEC4899); // Pink — QUIC
    case 'ssr':
    case 'shadowsocksr':
      return const Color(0xFF78716C); // Stone — legacy protocol
    case 'snell':
      return const Color(0xFF14B8A6); // Teal
    case 'socks5':
    case 'socks':
      return const Color(0xFF9CA3AF); // Gray — basic proxy
    case 'http':
      return const Color(0xFFA8A29E); // Warm gray — basic proxy
    case 'wireguard':
    case 'wg':
      return const Color(0xFF0EA5E9); // Sky blue — VPN tunnel
    case 'ssh':
      return const Color(0xFF84CC16); // Lime — terminal/shell
    default:
      return null;
  }
}
