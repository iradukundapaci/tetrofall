import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device can actually reach the internet, not merely has a link
/// (a captive portal reports wifi and still can't reach AdMob). The radio
/// state is only a hint that something changed; the published answer always
/// comes from a real lookup. [isOnline] starts false and is never optimistic.
class ConnectivityService {
  /// [probe] and [changes] let tests drive this without a platform channel.
  ConnectivityService({
    Future<bool> Function()? probe,
    Stream<List<ConnectivityResult>>? changes,
  }) : _probe = probe ?? _lookup,
       _changes = changes ?? Connectivity().onConnectivityChanged {
    _subscription = _changes.listen(_onConnectivityChanged);
    unawaited(_check());
  }

  /// Backoff for re-probing, which only runs while offline: once online, the
  /// radio stream reports it stopping.
  static const _firstRetry = Duration(seconds: 5);
  static const _maxRetry = Duration(seconds: 60);

  static const _probeTimeout = Duration(seconds: 5);

  final Future<bool> Function() _probe;
  final Stream<List<ConnectivityResult>> _changes;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  Duration _retryDelay = _firstRetry;
  bool _probing = false;
  bool _disposed = false;

  final ValueNotifier<bool> _isOnline = ValueNotifier(false);

  /// False until a probe proves otherwise, and again once the radio reports
  /// no link.
  ValueListenable<bool> get isOnline => _isOnline;

  /// Probes now instead of waiting out the backoff; called on app resume.
  void refresh() {
    if (_disposed) return;
    _resetRetry();
    unawaited(_check());
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    // The list is never empty, and `none` only ever appears alone.
    if (results.every((r) => r == ConnectivityResult.none)) {
      _setOnline(false);
      return;
    }
    // A link came up, but only the probe is trusted.
    _resetRetry();
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_disposed || _probing) return;
    _probing = true;
    try {
      _setOnline(await _probe());
    } catch (_) {
      // Any probe failure means offline; don't let it escape.
      _setOnline(false);
    } finally {
      _probing = false;
    }
  }

  void _setOnline(bool value) {
    if (_disposed) return;
    if (value) {
      _resetRetry();
    } else {
      _scheduleRetry();
    }
    _isOnline.value = value;
  }

  /// Drops any pending re-probe and the accumulated wait.
  void _resetRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDelay = _firstRetry;
  }

  /// Catches what the radio stream misses: a link that only just started
  /// resolving, and unreliable streams (iOS simulators).
  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    final delay = _retryDelay;
    _retryDelay = delay * 2 > _maxRetry ? _maxRetry : delay * 2;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_isOnline.value) unawaited(_check());
    });
  }

  static Future<bool> _lookup() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(_probeTimeout);
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      // The ordinary offline answer.
      return false;
    } on TimeoutException {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _isOnline.dispose();
  }
}
