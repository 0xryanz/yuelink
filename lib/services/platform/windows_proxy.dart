import 'dart:io';

/// Windows system proxy management via registry.
///
/// Sets/clears the Internet Settings proxy for the current user.
class WindowsProxy {
  static const _regPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// Enable system proxy.
  static Future<void> setProxy({
    required String host,
    required int httpPort,
  }) async {
    await Process.run('reg', [
      'add',
      _regPath,
      '/v',
      'ProxyEnable',
      '/t',
      'REG_DWORD',
      '/d',
      '1',
      '/f',
    ]);
    await Process.run('reg', [
      'add',
      _regPath,
      '/v',
      'ProxyServer',
      '/t',
      'REG_SZ',
      '/d',
      '$host:$httpPort',
      '/f',
    ]);
  }

  /// Disable system proxy.
  static Future<void> clearProxy() async {
    await Process.run('reg', [
      'add',
      _regPath,
      '/v',
      'ProxyEnable',
      '/t',
      'REG_DWORD',
      '/d',
      '0',
      '/f',
    ]);
  }
}
