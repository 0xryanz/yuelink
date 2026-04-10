import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../constants.dart';
import '../storage/settings_service.dart';
import 'service_client.dart';
import 'service_models.dart';

class ServiceManager {
  ServiceManager._();

  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  /// Expected service version — must match the Go binary's Version variable.
  /// Updated together with the Go build (set via -ldflags).
  static const expectedVersion = '1.0.12';

  static Future<DesktopServiceInfo> getInfo() async {
    if (!isSupported) {
      return DesktopServiceInfo.notInstalled();
    }

    final installed = await isInstalled();
    if (!installed) {
      return DesktopServiceInfo.notInstalled();
    }

    try {
      final status = await ServiceClient.status();
      // Version check: detect stale service binary after app update
      final remoteVersion = await ServiceClient.version();
      final versionMismatch =
          remoteVersion != null && remoteVersion != expectedVersion;
      return status.copyWith(
        serviceVersion: remoteVersion,
        needsReinstall: versionMismatch,
      );
    } catch (e) {
      return const DesktopServiceInfo(
        installed: true,
        reachable: false,
        mihomoRunning: false,
      ).copyWith(detail: e.toString().split('\n').first);
    }
  }

  static Future<bool> isInstalled() async {
    if (!isSupported) return false;

    if (Platform.isMacOS) {
      return File(_macPlistPath).existsSync() &&
          File(_macInstalledHelperPath).existsSync() &&
          File(_macInstalledMihomoPath).existsSync();
    }

    final result = await Process.run(
      'sc',
      ['query', AppConstants.desktopServiceName],
    );
    return result.exitCode == 0;
  }

  static Future<void> install() async {
    if (!isSupported) {
      throw UnsupportedError(
          'Desktop service mode is only available on macOS and Windows');
    }

    final token =
        await SettingsService.getServiceAuthToken() ?? _generateToken();
    await SettingsService.setServiceAuthToken(token);
    await SettingsService.setServicePort(AppConstants.serviceListenPort);

    final binaries = await _resolveSourceBinaries();
    final tempDir = await Directory.systemTemp.createTemp('yuelink_service_');

    try {
      final configFile = File('${tempDir.path}/service-config.json');
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'token': token,
          'listen_host': AppConstants.serviceListenHost,
          'listen_port': AppConstants.serviceListenPort,
          'mihomo_path': Platform.isMacOS
              ? _macInstalledMihomoPath
              : _windowsInstalledMihomoPath,
          'helper_log_path': Platform.isMacOS
              ? _macInstalledHelperLogPath
              : _windowsInstalledHelperLogPath,
        }),
      );

      if (Platform.isMacOS) {
        final script = File('${tempDir.path}/install_service.sh');
        await script.writeAsString(
          _macInstallScript(
            helperSource: binaries.helperPath,
            mihomoSource: binaries.mihomoPath,
            configSource: configFile.path,
          ),
        );
        await script.setLastModified(DateTime.now());
        await Process.run('chmod', ['700', script.path]);
        await _runMacElevated(script.path);
      } else if (Platform.isWindows) {
        final script = File('${tempDir.path}/install_service.ps1');
        await script.writeAsString(
          _windowsInstallScript(
            helperSource: binaries.helperPath,
            mihomoSource: binaries.mihomoPath,
            configSource: configFile.path,
          ),
        );
        await _runWindowsElevated(script.path);
      }

      await _waitUntilReachable();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> uninstall() async {
    if (!isSupported) return;

    final tempDir = await Directory.systemTemp.createTemp('yuelink_service_');
    try {
      if (Platform.isMacOS) {
        final script = File('${tempDir.path}/uninstall_service.sh');
        await script.writeAsString(_macUninstallScript());
        await Process.run('chmod', ['700', script.path]);
        await _runMacElevated(script.path);
      } else if (Platform.isWindows) {
        final script = File('${tempDir.path}/uninstall_service.ps1');
        await script.writeAsString(_windowsUninstallScript());
        await _runWindowsElevated(script.path);
      }
    } finally {
      await SettingsService.setServiceAuthToken(null);
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<_ServiceBinaries> _resolveSourceBinaries() async {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    final helperCandidates = <String>[];
    final mihomoCandidates = <String>[];

    if (Platform.isMacOS) {
      helperCandidates.addAll([
        '$execDir/../Frameworks/yuelink-service-helper',
        '$execDir/../Resources/yuelink-service-helper',
        '$cwd/macos/Frameworks/yuelink-service-helper',
        '$cwd/service/build/macos-universal/yuelink-service-helper',
        '$cwd/service/build/macos-arm64/yuelink-service-helper',
        '$cwd/service/build/macos-amd64/yuelink-service-helper',
      ]);
      mihomoCandidates.addAll([
        '$execDir/../Frameworks/yuelink-mihomo',
        '$execDir/../Resources/yuelink-mihomo',
        '$cwd/macos/Frameworks/yuelink-mihomo',
        '$cwd/service/build/macos-universal/yuelink-mihomo',
        '$cwd/service/build/macos-arm64/yuelink-mihomo',
        '$cwd/service/build/macos-amd64/yuelink-mihomo',
      ]);
    } else if (Platform.isWindows) {
      helperCandidates.addAll([
        '$execDir\\yuelink-service-helper.exe',
        '$cwd\\windows\\libs\\amd64\\yuelink-service-helper.exe',
        '$cwd\\windows\\libs\\arm64\\yuelink-service-helper.exe',
        '$cwd\\service\\build\\windows-amd64\\yuelink-service-helper.exe',
        '$cwd\\service\\build\\windows-arm64\\yuelink-service-helper.exe',
      ]);
      mihomoCandidates.addAll([
        '$execDir\\yuelink-mihomo.exe',
        '$cwd\\windows\\libs\\amd64\\yuelink-mihomo.exe',
        '$cwd\\windows\\libs\\arm64\\yuelink-mihomo.exe',
        '$cwd\\service\\build\\windows-amd64\\yuelink-mihomo.exe',
        '$cwd\\service\\build\\windows-arm64\\yuelink-mihomo.exe',
      ]);
    }

    final helperPath = helperCandidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => '',
    );
    final mihomoPath = mihomoCandidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => '',
    );

    if (helperPath.isEmpty || mihomoPath.isEmpty) {
      throw const FileSystemException(
        'Desktop service binaries are missing. '
        'Build and bundle yuelink-service-helper and yuelink-mihomo first.',
      );
    }

    return _ServiceBinaries(
      helperPath: helperPath,
      mihomoPath: mihomoPath,
    );
  }

  static Future<void> _waitUntilReachable() async {
    for (var i = 0; i < 20; i++) {
      if (await ServiceClient.ping()) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw const ProcessException(
      'service',
      [],
      'Desktop service installed but helper did not become reachable in time',
    );
  }

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Future<void> _runMacElevated(String scriptPath) async {
    final command =
        'do shell script "${_appleScriptEscape('/bin/sh ${_shellQuote(scriptPath)}')}" with administrator privileges';
    final result = await Process.run('osascript', ['-e', command]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'osascript',
        ['-e', command],
        '${result.stderr}'.trim().isEmpty
            ? '${result.stdout}'.trim()
            : '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  static Future<void> _runWindowsElevated(String scriptPath) async {
    final launcher = r'''
$ErrorActionPreference = "Stop"
$scriptPath = __SCRIPT__
$process = Start-Process PowerShell -Verb RunAs -Wait -PassThru -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', $scriptPath
)
exit $process.ExitCode
'''
        .replaceAll('__SCRIPT__', _powershellQuoted(scriptPath));

    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-Command', launcher],
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell',
        ['-NoProfile', '-Command', launcher],
        '${result.stderr}'.trim().isEmpty
            ? '${result.stdout}'.trim()
            : '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  static String _macInstallScript({
    required String helperSource,
    required String mihomoSource,
    required String configSource,
  }) {
    return '''
#!/bin/sh
set -eu

SERVICE_DIR=${_shellQuote(_macServiceDir)}
HELPER_SRC=${_shellQuote(helperSource)}
MIHOMO_SRC=${_shellQuote(mihomoSource)}
CONFIG_SRC=${_shellQuote(configSource)}

mkdir -p "${r'$'}SERVICE_DIR"
cp "${r'$'}HELPER_SRC" ${_shellQuote(_macInstalledHelperPath)}
cp "${r'$'}MIHOMO_SRC" ${_shellQuote(_macInstalledMihomoPath)}
cp "${r'$'}CONFIG_SRC" ${_shellQuote(_macInstalledConfigPath)}

chmod 755 ${_shellQuote(_macInstalledHelperPath)} ${_shellQuote(_macInstalledMihomoPath)}
chmod 600 ${_shellQuote(_macInstalledConfigPath)}
chown root:wheel ${_shellQuote(_macInstalledHelperPath)} ${_shellQuote(_macInstalledMihomoPath)} ${_shellQuote(_macInstalledConfigPath)}

cat > ${_shellQuote(_macPlistPath)} <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AppConstants.desktopServiceLabel}</string>
  <key>ProgramArguments</key>
  <array>
    <string>$_macInstalledHelperPath</string>
    <string>-config</string>
    <string>$_macInstalledConfigPath</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$_macInstalledHelperLogPath</string>
  <key>StandardErrorPath</key>
  <string>$_macInstalledHelperLogPath</string>
</dict>
</plist>
PLIST

chmod 644 ${_shellQuote(_macPlistPath)}
chown root:wheel ${_shellQuote(_macPlistPath)}

launchctl bootout system/${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
launchctl bootstrap system ${_shellQuote(_macPlistPath)}
launchctl kickstart -k system/${AppConstants.desktopServiceLabel}
''';
  }

  static String _macUninstallScript() {
    return '''
#!/bin/sh
set -eu

launchctl bootout system/${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
rm -f ${_shellQuote(_macPlistPath)}
rm -rf ${_shellQuote(_macServiceDir)}
''';
  }

  static String _windowsInstallScript({
    required String helperSource,
    required String mihomoSource,
    required String configSource,
  }) {
    return r'''
$ErrorActionPreference = "Stop"

$serviceName = '__SERVICE_NAME__'
$serviceDir = __SERVICE_DIR__
$helperSrc = __HELPER_SRC__
$mihomoSrc = __MIHOMO_SRC__
$configSrc = __CONFIG_SRC__
$helperDst = __HELPER_DST__
$mihomoDst = __MIHOMO_DST__
$configDst = __CONFIG_DST__

if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
  Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
  sc.exe delete $serviceName | Out-Null
  Start-Sleep -Seconds 1
}

New-Item -ItemType Directory -Force -Path $serviceDir | Out-Null
Copy-Item -Force $helperSrc $helperDst
Copy-Item -Force $mihomoSrc $mihomoDst
Copy-Item -Force $configSrc $configDst

$binPath = '"' + $helperDst + '" -config "' + $configDst + '"'
New-Service -Name $serviceName -BinaryPathName $binPath -DisplayName 'YueLink Service Helper' -StartupType Automatic | Out-Null
sc.exe description $serviceName "Privileged YueLink desktop TUN helper" | Out-Null
Start-Service -Name $serviceName
'''
        .replaceAll('__SERVICE_NAME__', AppConstants.desktopServiceName)
        .replaceAll('__SERVICE_DIR__', _powershellQuoted(_windowsServiceDir))
        .replaceAll('__HELPER_SRC__', _powershellQuoted(helperSource))
        .replaceAll('__MIHOMO_SRC__', _powershellQuoted(mihomoSource))
        .replaceAll('__CONFIG_SRC__', _powershellQuoted(configSource))
        .replaceAll(
            '__HELPER_DST__', _powershellQuoted(_windowsInstalledHelperPath))
        .replaceAll(
            '__MIHOMO_DST__', _powershellQuoted(_windowsInstalledMihomoPath))
        .replaceAll(
            '__CONFIG_DST__', _powershellQuoted(_windowsInstalledConfigPath));
  }

  static String _windowsUninstallScript() {
    return r'''
$ErrorActionPreference = "Stop"
$serviceName = '__SERVICE_NAME__'
$serviceDir = __SERVICE_DIR__

if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
  Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
  sc.exe delete $serviceName | Out-Null
  Start-Sleep -Seconds 1
}

if (Test-Path $serviceDir) {
  Remove-Item -Path $serviceDir -Recurse -Force
}
'''
        .replaceAll('__SERVICE_NAME__', AppConstants.desktopServiceName)
        .replaceAll('__SERVICE_DIR__', _powershellQuoted(_windowsServiceDir));
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  static String _appleScriptEscape(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  static String _powershellQuoted(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  static String get _macServiceDir =>
      '/Library/Application Support/YueLink/Service';
  static String get _macInstalledHelperPath =>
      '$_macServiceDir/yuelink-service-helper';
  static String get _macInstalledMihomoPath => '$_macServiceDir/yuelink-mihomo';
  static String get _macInstalledConfigPath =>
      '$_macServiceDir/service-config.json';
  static String get _macInstalledHelperLogPath => '$_macServiceDir/helper.log';
  static String get _macPlistPath =>
      '/Library/LaunchDaemons/${AppConstants.desktopServiceLabel}.plist';

  static String get _windowsProgramData =>
      Platform.environment['ProgramData'] ?? r'C:\ProgramData';
  static String get _windowsServiceDir =>
      '$_windowsProgramData\\YueLink\\Service';
  static String get _windowsInstalledHelperPath =>
      '$_windowsServiceDir\\yuelink-service-helper.exe';
  static String get _windowsInstalledMihomoPath =>
      '$_windowsServiceDir\\yuelink-mihomo.exe';
  static String get _windowsInstalledConfigPath =>
      '$_windowsServiceDir\\service-config.json';
  static String get _windowsInstalledHelperLogPath =>
      '$_windowsServiceDir\\helper.log';
}

class _ServiceBinaries {
  final String helperPath;
  final String mihomoPath;

  const _ServiceBinaries({
    required this.helperPath,
    required this.mihomoPath,
  });
}
