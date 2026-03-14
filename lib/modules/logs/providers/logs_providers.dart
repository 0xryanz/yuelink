import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/core_mock.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/datasources/mihomo_stream.dart';
import '../../../infrastructure/repositories/log_repository.dart';
import '../../../providers/core_provider.dart';

// Re-export logLevelProvider so it can be accessed via this module too
export '../../../providers/core_provider.dart' show logLevelProvider;

/// Live log entries from mihomo.
final logEntriesProvider =
    StateNotifierProvider<LogEntriesNotifier, List<LogEntry>>(
  (ref) => LogEntriesNotifier(ref),
);

class LogEntriesNotifier extends StateNotifier<List<LogEntry>> {
  final Ref ref;
  StreamSubscription? _sub;
  Timer? _mockTimer;
  static const _maxEntries = 500;

  LogEntriesNotifier(this.ref) : super([]) {
    ref.listen(coreStatusProvider, (prev, next) {
      if (next == CoreStatus.running) {
        _startListening();
      } else if (next == CoreStatus.stopped) {
        _stopListening();
        state = [];
      }
    });
    // Restart stream when log level changes while core is running
    ref.listen(logLevelProvider, (prev, next) {
      if (prev != next && ref.read(coreStatusProvider) == CoreStatus.running) {
        _startListening(); // _startListening calls _stopListening first
      }
    });
  }

  void _startListening() {
    // Ensure old subscription is fully cleaned before starting new one
    _stopListening();

    final manager = CoreManager.instance;
    final level = ref.read(logLevelProvider);

    if (manager.isMockMode) {
      // Generate mock log entries periodically
      final mockLogs = CoreMock.instance.getLogs();
      var index = 0;
      _mockTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted) return;
        final entry = mockLogs[index % mockLogs.length];
        _addEntry(LogEntry(
          type: entry['type'] ?? 'info',
          payload: entry['payload'] ?? '',
        ));
        index++;
      });
    } else {
      // Connect via LogRepository (goes through infrastructure layer)
      final repo = ref.read(logRepositoryProvider);
      _sub = repo.logStream(level: level).listen((entry) {
        if (mounted) _addEntry(entry);
      });
    }
  }

  void _addEntry(LogEntry entry) {
    if (state.length >= _maxEntries) {
      // Avoid copying the full list + trimming; just take the tail we need
      state = [entry, ...state.take(_maxEntries - 1)];
    } else {
      state = [entry, ...state];
    }
  }

  void _stopListening() {
    _sub?.cancel();
    _sub = null;
    _mockTimer?.cancel();
    _mockTimer = null;
  }

  void clear() => state = [];

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }
}
