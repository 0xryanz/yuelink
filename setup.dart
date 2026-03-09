// ignore_for_file: avoid_print
// YueLink build orchestrator
// Compiles the Go (mihomo) core into platform-native shared/static libraries.
//
// Usage:
//   dart setup.dart <command> [options]
//
// Commands:
//   build   Build the Go core for a specific platform
//   clean   Remove all compiled core artifacts
//
// Build options:
//   --platform, -p   Target platform: android, ios, macos, windows, linux
//   --arch, -a       Target architecture: arm64, amd64, arm (default: host arch)
//   --debug          Build with debug symbols (default: release)
//
// Examples:
//   dart setup.dart build -p android
//   dart setup.dart build -p android -a arm64
//   dart setup.dart build -p ios
//   dart setup.dart build -p macos -a arm64
//   dart setup.dart build -p windows -a amd64
//   dart setup.dart clean

import 'dart:io';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String corePath = 'core';
const String outputDir = 'core/build';

/// Android API level for the NDK toolchain.
const String androidApiLevel = '21';

/// Map of (platform, arch) → output file name.
const Map<String, Map<String, String>> outputNames = {
  'android': {
    'arm64': 'android-arm64/libclash.so',
    'arm': 'android-arm/libclash.so',
    'amd64': 'android-x86_64/libclash.so',
  },
  'ios': {
    'arm64': 'ios-arm64/libclash.a',
  },
  'macos': {
    'arm64': 'macos-arm64/libclash.dylib',
    'amd64': 'macos-amd64/libclash.dylib',
  },
  'windows': {
    'amd64': 'windows-amd64/libclash.dll',
    'arm64': 'windows-arm64/libclash.dll',
  },
  'linux': {
    'amd64': 'linux-amd64/libclash.so',
    'arm64': 'linux-arm64/libclash.so',
  },
};

/// Android NDK triple for each architecture.
const Map<String, String> androidNdkTriple = {
  'arm64': 'aarch64-linux-android',
  'arm': 'armv7a-linux-androideabi',
  'amd64': 'x86_64-linux-android',
};

/// Go GOARCH values.
const Map<String, String> goArchMap = {
  'arm64': 'arm64',
  'arm': 'arm',
  'amd64': 'amd64',
  'x86_64': 'amd64',
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns the host architecture mapped to our canonical names.
String get hostArch {
  final result = Process.runSync('uname', ['-m']);
  final raw = (result.stdout as String).trim();
  if (raw == 'x86_64') return 'amd64';
  if (raw == 'aarch64' || raw == 'arm64') return 'arm64';
  return raw;
}

/// Returns the host OS.
String get hostOS {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  throw Exception('Unsupported host OS');
}

/// Resolve the Android NDK path.
String resolveAndroidNdk() {
  // 1. ANDROID_NDK env var
  final envNdk = Platform.environment['ANDROID_NDK'];
  if (envNdk != null && Directory(envNdk).existsSync()) return envNdk;

  // 2. ANDROID_NDK_HOME env var
  final envNdkHome = Platform.environment['ANDROID_NDK_HOME'];
  if (envNdkHome != null && Directory(envNdkHome).existsSync()) return envNdkHome;

  // 3. Derive from ANDROID_HOME / ANDROID_SDK_ROOT
  final sdkRoot =
      Platform.environment['ANDROID_HOME'] ?? Platform.environment['ANDROID_SDK_ROOT'];
  if (sdkRoot != null) {
    final ndkDir = Directory('$sdkRoot/ndk');
    if (ndkDir.existsSync()) {
      // Pick the latest installed NDK version
      final versions = ndkDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split('/').last)
          .where((name) => !name.startsWith('.'))
          .toList()
        ..sort();
      if (versions.isNotEmpty) {
        return '${ndkDir.path}/${versions.last}';
      }
    }
  }

  throw Exception(
    'Cannot find Android NDK. Set ANDROID_NDK, ANDROID_NDK_HOME, or ANDROID_HOME env var.',
  );
}

/// Find the NDK C compiler for the given arch.
String resolveAndroidCC(String ndkPath, String arch) {
  final triple = androidNdkTriple[arch]!;
  final hostTag = Platform.isMacOS ? 'darwin-x86_64' : 'linux-x86_64';
  final prebuilt = '$ndkPath/toolchains/llvm/prebuilt/$hostTag/bin';

  // clang binary: <triple><api>-clang
  final clang = '$prebuilt/$triple$androidApiLevel-clang';
  if (File(clang).existsSync()) return clang;

  // Try without API level suffix (newer NDK)
  final clangNoApi = '$prebuilt/$triple-clang';
  if (File(clangNoApi).existsSync()) return clangNoApi;

  throw Exception('Cannot find Android clang at: $clang');
}

/// Run a command, printing it and streaming output. Throws on failure.
Future<void> run(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
}) async {
  final envDisplay =
      environment?.entries.map((e) => '${e.key}=${e.value}').join(' ') ?? '';
  print('\n\$ ${envDisplay.isNotEmpty ? "$envDisplay " : ""}$executable ${args.join(" ")}');

  final process = await Process.start(
    executable,
    args,
    environment: environment,
    workingDirectory: workingDirectory,
    includeParentEnvironment: true,
  );

  process.stdout.listen((data) => stdout.add(data));
  process.stderr.listen((data) => stderr.add(data));

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception('Command failed with exit code $exitCode');
  }
}

// ---------------------------------------------------------------------------
// Build logic
// ---------------------------------------------------------------------------

Future<void> buildCore({
  required String platform,
  required String arch,
  required bool debug,
}) async {
  final goArch = goArchMap[arch] ?? arch;
  final platformArchNames = outputNames[platform];
  if (platformArchNames == null) {
    throw Exception('Unsupported platform: $platform');
  }
  final outName = platformArchNames[arch];
  if (outName == null) {
    throw Exception('Unsupported arch "$arch" for platform "$platform"');
  }

  final outPath = '$outputDir/$outName';
  final outDir = File(outPath).parent;
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // Common environment
  final env = <String, String>{
    'CGO_ENABLED': '1',
  };

  // Common ldflags
  final ldflags = <String>[
    if (!debug) '-s',
    if (!debug) '-w',
    '-X "github.com/metacubex/mihomo/constant.Version=yuelink"',
  ];

  String buildMode;
  List<String> extraArgs = [];

  switch (platform) {
    // -----------------------------------------------------------------
    // Android
    // -----------------------------------------------------------------
    case 'android':
      final ndkPath = resolveAndroidNdk();
      final cc = resolveAndroidCC(ndkPath, arch);
      env['GOOS'] = 'android';
      env['GOARCH'] = goArch;
      env['CC'] = cc;
      if (arch == 'arm') {
        env['GOARM'] = '7';
      }
      buildMode = 'c-shared';
      break;

    // -----------------------------------------------------------------
    // iOS — must be c-archive (static library)
    // -----------------------------------------------------------------
    case 'ios':
      if (arch != 'arm64') {
        throw Exception('iOS only supports arm64');
      }
      // Find the iOS SDK clang
      final sdkResult = Process.runSync('xcrun', ['--sdk', 'iphoneos', '--show-sdk-path']);
      final sdkPath = (sdkResult.stdout as String).trim();
      final ccResult = Process.runSync('xcrun', ['--sdk', 'iphoneos', '--find', 'clang']);
      final cc = (ccResult.stdout as String).trim();

      env['GOOS'] = 'ios';
      env['GOARCH'] = 'arm64';
      env['CC'] = cc;
      env['CGO_CFLAGS'] = '-isysroot $sdkPath -arch arm64 -miphoneos-version-min=15.0';
      env['CGO_LDFLAGS'] = '-isysroot $sdkPath -arch arm64 -miphoneos-version-min=15.0';
      buildMode = 'c-archive';
      break;

    // -----------------------------------------------------------------
    // macOS
    // -----------------------------------------------------------------
    case 'macos':
      env['GOOS'] = 'darwin';
      env['GOARCH'] = goArch;
      // Use system clang
      if (arch == 'amd64' && hostArch == 'arm64') {
        // Cross-compile on Apple Silicon → Intel
        env['CC'] = 'clang -arch x86_64';
      } else if (arch == 'arm64' && hostArch == 'amd64') {
        env['CC'] = 'clang -arch arm64';
      }
      buildMode = 'c-shared';
      break;

    // -----------------------------------------------------------------
    // Windows
    // -----------------------------------------------------------------
    case 'windows':
      env['GOOS'] = 'windows';
      env['GOARCH'] = goArch;
      if (hostOS != 'windows') {
        // Cross-compile from macOS/Linux
        if (arch == 'amd64') {
          env['CC'] = 'x86_64-w64-mingw32-gcc';
        } else if (arch == 'arm64') {
          env['CC'] = 'aarch64-w64-mingw32-gcc';
        }
      }
      buildMode = 'c-shared';
      break;

    // -----------------------------------------------------------------
    // Linux
    // -----------------------------------------------------------------
    case 'linux':
      env['GOOS'] = 'linux';
      env['GOARCH'] = goArch;
      if (arch != hostArch) {
        if (arch == 'arm64') {
          env['CC'] = 'aarch64-linux-gnu-gcc';
        } else if (arch == 'amd64') {
          env['CC'] = 'x86_64-linux-gnu-gcc';
        }
      }
      buildMode = 'c-shared';
      break;

    default:
      throw Exception('Unknown platform: $platform');
  }

  print('');
  print('═══════════════════════════════════════════════════════');
  print('  Building YueLink core');
  print('  Platform : $platform');
  print('  Arch     : $arch (GOARCH=$goArch)');
  print('  Mode     : $buildMode');
  print('  Output   : $outPath');
  print('  Debug    : $debug');
  print('═══════════════════════════════════════════════════════');

  await run(
    'go',
    [
      'build',
      '-buildmode=$buildMode',
      '-trimpath',
      '-ldflags=${ldflags.join(" ")}',
      ...extraArgs,
      '-o',
      '../$outPath', // relative to core/
      '.',
    ],
    environment: env,
    workingDirectory: corePath,
  );

  final fileSize = File(outPath).lengthSync();
  final sizeMb = (fileSize / 1024 / 1024).toStringAsFixed(1);
  print('\n✅ Built successfully: $outPath ($sizeMb MB)');
}

/// Build all architectures for a given platform.
Future<void> buildPlatformAll(String platform, {required bool debug}) async {
  final arches = outputNames[platform]!.keys.toList();
  for (final arch in arches) {
    await buildCore(platform: platform, arch: arch, debug: debug);
  }
}

/// Copy built libraries to the correct Flutter platform directories.
Future<void> installLibraries(String platform) async {
  switch (platform) {
    case 'android':
      // Copy .so files to android/app/src/main/jniLibs/
      final archDirMap = {
        'arm64': 'arm64-v8a',
        'arm': 'armeabi-v7a',
        'amd64': 'x86_64',
      };
      for (final entry in archDirMap.entries) {
        final src = '$outputDir/android-${entry.key}/libclash.so';
        final dst = 'android/app/src/main/jniLibs/${entry.value}/libclash.so';
        if (File(src).existsSync()) {
          File(dst).parent.createSync(recursive: true);
          File(src).copySync(dst);
          print('📦 Installed: $dst');
        }
      }
      break;

    case 'ios':
      final src = '$outputDir/ios-arm64/libclash.a';
      final dst = 'ios/Runner/Frameworks/libclash.a';
      if (File(src).existsSync()) {
        File(dst).parent.createSync(recursive: true);
        File(src).copySync(dst);
        print('📦 Installed: $dst');
      }
      // Also copy the header
      final hSrc = '$outputDir/ios-arm64/libclash.h';
      final hDst = 'ios/Runner/Frameworks/libclash.h';
      if (File(hSrc).existsSync()) {
        File(hSrc).copySync(hDst);
        print('📦 Installed: $hDst');
      }
      break;

    case 'macos':
      for (final arch in ['arm64', 'amd64']) {
        final src = '$outputDir/macos-$arch/libclash.dylib';
        final dst = 'macos/Frameworks/libclash-$arch.dylib';
        if (File(src).existsSync()) {
          File(dst).parent.createSync(recursive: true);
          File(src).copySync(dst);
          print('📦 Installed: $dst');
        }
      }
      break;

    case 'windows':
      for (final arch in ['amd64', 'arm64']) {
        final src = '$outputDir/windows-$arch/libclash.dll';
        final dst = 'windows/libs/$arch/libclash.dll';
        if (File(src).existsSync()) {
          File(dst).parent.createSync(recursive: true);
          File(src).copySync(dst);
          print('📦 Installed: $dst');
        }
      }
      break;

    case 'linux':
      for (final arch in ['amd64', 'arm64']) {
        final src = '$outputDir/linux-$arch/libclash.so';
        final dst = 'linux/libs/$arch/libclash.so';
        if (File(src).existsSync()) {
          File(dst).parent.createSync(recursive: true);
          File(src).copySync(dst);
          print('📦 Installed: $dst');
        }
      }
      break;
  }
}

/// Remove all build artifacts.
void cleanBuild() {
  final dir = Directory(outputDir);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
    print('🧹 Cleaned: $outputDir');
  } else {
    print('Nothing to clean.');
  }

  // Also clean installed libraries
  final installDirs = [
    'android/app/src/main/jniLibs',
    'ios/Runner/Frameworks',
    'macos/Frameworks',
    'windows/libs',
    'linux/libs',
  ];
  for (final path in installDirs) {
    final d = Directory(path);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
      print('🧹 Cleaned: $path');
    }
  }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

void printUsage() {
  print('''
YueLink Build Tool

Usage:
  dart setup.dart <command> [options]

Commands:
  build     Build the Go core library
  install   Copy built libraries to Flutter platform directories
  clean     Remove all build artifacts

Build options:
  -p, --platform   android | ios | macos | windows | linux | all
  -a, --arch       arm64 | amd64 | arm (default: all arches for the platform)
  --debug          Include debug symbols

Examples:
  dart setup.dart build -p android               # Build all Android arches
  dart setup.dart build -p android -a arm64       # Build Android arm64 only
  dart setup.dart build -p ios                    # Build iOS (arm64 only)
  dart setup.dart build -p macos                  # Build macOS (arm64 + amd64)
  dart setup.dart build -p windows -a amd64       # Build Windows x64
  dart setup.dart install -p android              # Copy .so to jniLibs/
  dart setup.dart clean                           # Remove all artifacts
''');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    printUsage();
    exit(1);
  }

  final command = args[0];

  // Parse flags
  String? platform;
  String? arch;
  bool debug = false;

  for (int i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '-p':
      case '--platform':
        platform = args[++i];
        break;
      case '-a':
      case '--arch':
        arch = args[++i];
        break;
      case '--debug':
        debug = true;
        break;
      default:
        print('Unknown option: ${args[i]}');
        printUsage();
        exit(1);
    }
  }

  switch (command) {
    case 'build':
      if (platform == null) {
        print('Error: --platform is required for build command.');
        exit(1);
      }

      // Verify Go is installed
      final goCheck = Process.runSync('go', ['version']);
      if (goCheck.exitCode != 0) {
        print('Error: Go is not installed or not in PATH.');
        print('Install Go from https://go.dev/dl/');
        exit(1);
      }
      print('Go: ${(goCheck.stdout as String).trim()}');

      // Verify core directory exists
      if (!Directory(corePath).existsSync()) {
        print('Error: core/ directory not found.');
        print('Run: cd core && git submodule update --init');
        exit(1);
      }

      if (platform == 'all') {
        for (final p in outputNames.keys) {
          await buildPlatformAll(p, debug: debug);
        }
      } else if (arch != null) {
        await buildCore(platform: platform, arch: arch, debug: debug);
      } else {
        await buildPlatformAll(platform, debug: debug);
      }
      break;

    case 'install':
      if (platform == null) {
        print('Error: --platform is required for install command.');
        exit(1);
      }
      if (platform == 'all') {
        for (final p in outputNames.keys) {
          await installLibraries(p);
        }
      } else {
        await installLibraries(platform);
      }
      break;

    case 'clean':
      cleanBuild();
      break;

    default:
      print('Unknown command: $command');
      printUsage();
      exit(1);
  }
}
