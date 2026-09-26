import 'package:flutter/widgets.dart';

import 'storage_service.dart';
import 'telemetry.dart';

/// A session is a foreground stretch of the app; returning after [_idleGap] in
/// the background starts a new one.
abstract final class SessionTracker {
  static const _idleGap = Duration(minutes: 30);

  static DateTime? _start;
  static DateTime? _pausedAt;
  static int _index = 0;
  static AppLifecycleListener? _listener;
  static StorageService? _storage;

  /// How long the current session has been running.
  static Duration get elapsed {
    final start = _start;
    return start == null ? Duration.zero : DateTime.now().difference(start);
  }

  /// Call once at launch, after the binding exists.
  static Future<void> begin(StorageService storage) async {
    _storage = storage;
    await _startSession();
    _listener ??= AppLifecycleListener(onStateChange: _onStateChange);
  }

  static Future<void> _startSession() async {
    final storage = _storage;
    if (storage == null) return;
    _index = await storage.incrementSessionCount();
    _start = DateTime.now();
    Telemetry.sessionStart(index: _index);
  }

  static void _onStateChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _pausedAt ??= DateTime.now();
        Telemetry.sessionEnd(index: _index, durationSeconds: elapsed.inSeconds);
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        _pausedAt = null;
        if (pausedAt != null &&
            DateTime.now().difference(pausedAt) >= _idleGap) {
          _startSession();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
