class DesktopServiceInfo {
  final bool installed;
  final bool reachable;
  final bool mihomoRunning;
  final int? pid;
  final String? homeDir;
  final String? configPath;
  final String? logPath;
  final String? startedAt;
  final String? lastExit;
  final String? lastError;
  final String? detail;
  final String? serviceVersion;
  final bool needsReinstall;

  const DesktopServiceInfo({
    required this.installed,
    required this.reachable,
    required this.mihomoRunning,
    this.pid,
    this.homeDir,
    this.configPath,
    this.logPath,
    this.startedAt,
    this.lastExit,
    this.lastError,
    this.detail,
    this.serviceVersion,
    this.needsReinstall = false,
  });

  factory DesktopServiceInfo.notInstalled() {
    return const DesktopServiceInfo(
      installed: false,
      reachable: false,
      mihomoRunning: false,
    );
  }

  factory DesktopServiceInfo.fromJson(
    Map<String, dynamic> json, {
    required bool installed,
    required bool reachable,
    String? detail,
    String? serviceVersion,
    bool needsReinstall = false,
  }) {
    return DesktopServiceInfo(
      installed: installed,
      reachable: reachable,
      mihomoRunning: json['running'] == true,
      pid: (json['pid'] as num?)?.toInt(),
      homeDir: json['home_dir'] as String?,
      configPath: json['config_path'] as String?,
      logPath: json['log_path'] as String?,
      startedAt: json['started_at'] as String?,
      lastExit: json['last_exit'] as String?,
      lastError: json['last_error'] as String?,
      detail: detail,
      serviceVersion: serviceVersion,
      needsReinstall: needsReinstall,
    );
  }

  DesktopServiceInfo copyWith({
    bool? installed,
    bool? reachable,
    bool? mihomoRunning,
    int? pid,
    String? homeDir,
    String? configPath,
    String? logPath,
    String? startedAt,
    String? lastExit,
    String? lastError,
    String? detail,
    String? serviceVersion,
    bool? needsReinstall,
  }) {
    return DesktopServiceInfo(
      installed: installed ?? this.installed,
      reachable: reachable ?? this.reachable,
      mihomoRunning: mihomoRunning ?? this.mihomoRunning,
      pid: pid ?? this.pid,
      homeDir: homeDir ?? this.homeDir,
      configPath: configPath ?? this.configPath,
      logPath: logPath ?? this.logPath,
      startedAt: startedAt ?? this.startedAt,
      lastExit: lastExit ?? this.lastExit,
      lastError: lastError ?? this.lastError,
      detail: detail ?? this.detail,
      serviceVersion: serviceVersion ?? this.serviceVersion,
      needsReinstall: needsReinstall ?? this.needsReinstall,
    );
  }
}
