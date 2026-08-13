import 'package:flutter/foundation.dart';

/// Singleton utility for collecting in-app telemetry logs and debugging audio service lifecycle.
class DebugLogger {
  DebugLogger._();

  static final List<String> _logs = [];
  
  /// ValueNotifier exposing the current log history for UI reactivity.
  static final ValueNotifier<List<String>> logsNotifier = ValueNotifier<List<String>>([]);

  /// Appends a new timestamped log entry.
  static void log(String message) {
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final formatted = '[$timestamp] $message';

    debugPrint(formatted);
    _logs.add(formatted);
    
    // Cap memory footprint to last 500 entries
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    
    logsNotifier.value = List.unmodifiable(_logs);
  }

  /// Returns all collected logs as a single multiline string.
  static String getAllLogs() => _logs.join('\n');

  /// Clears all collected logs.
  static void clear() {
    _logs.clear();
    logsNotifier.value = List.unmodifiable(_logs);
  }
}
