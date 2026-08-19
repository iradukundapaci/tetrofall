import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device can actually reach the internet, as opposed to whether
/// it has a link.
///
/// The distinction matters here because everything downstream is an ad
/// request: a phone on hotel wifi behind a captive portal reports
/// [ConnectivityResult.wifi] and still cannot talk to AdMob. So the radio
/// state from `connectivity_plus` is used only as a *hint* that something
/// changed, and the answer this class publishes always comes from an actual
/// lookup.
///
/// [isOnline] starts false and is never optimistic — callers wait for it to
/// turn true rather than trying and failing.
class ConnectivityService {
  /// [probe] and [changes] exist so tests can drive this without a platform
  /// channel or a DNS server; production passes neither.
  ConnectivityService({
    Future<bool> Function()? probe,
    Stream<List<ConnectivityResult>>? changes,
  }) : _probe = probe ?? _lookup,
       _changes = changes ?? Connectivity().onConnectivityChanged {
    _subscription = _changes.listen(_onConnectivityChanged);
    unawaited(_check());
  }

  /// Backoff for re-probing while offline. Only runs while offline: once the
  /// answer is true, the radio stream is enough to tell us it stopped being
  /// true, and a timer polling DNS forever would be a battery cost for
  /// nothing.
  static const _firstRetry = Duration(seconds: 5);
  static const _maxRetry = Duration(seconds: 60);

  /// Short enough that a dead network doesn't hold a probe open across a
  /// backoff step, long enough for a slow mobile connection to answer.
  static const _probeTimeout = Duration(seconds: 5);

  final Future<bool> Function() _probe;
  final Stream<List<ConnectivityResult>> _changes;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  Duration _retryDelay = _firstRetry;
  bool _probing = false;
  bool _disposed = false;

  final ValueNotifier<bool> _isOnline = ValueNotifier(false);

  /// False until a probe has proven otherwise, and back to false the moment
  /// the radio reports no link.
  ValueListenable<bool> get isOnline => _isOnline;

  /// Probes now instead of waiting out the backoff. Called when the app is
  /// resumed: coming back from the background is the single most likely moment
  /// for the network to have changed while nobody was listening.
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
    // A link came up — but that is exactly the claim we don't trust, so the
    // backoff is reset and the answer comes from the probe.
    _resetRetry();
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_disposed || _probing) return;
    _probing = true;
    try {
      _setOnline(await _probe());
    } catch (_) {
      // Anything the probe throws means the same thing here, and letting it
      // escape would put an unhandled error in the zone over what is, at
      // worst, a wrong guess we will make again in a few seconds.
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

  /// Drops any pending re-probe and forgets the accumulated wait. Cancelling
  /// matters as much as the delay does: a timer already counting down a
  /// minute would otherwise swallow the whole point of resetting.
  void _resetRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDelay = _firstRetry;
  }

  /// Catches what the radio stream misses: a link that was up all along but
  /// only just started resolving, and platforms where the stream is unreliable
  /// (iOS simulators, notably).
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
      // The ordinary offline answer, not a fault worth reporting.
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
