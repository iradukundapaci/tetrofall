import 'package:flutter/foundation.dart';

import '../game/config/economy_tuning.dart';
import 'storage_service.dart';

/// The remaining balance of timed ad-free play ("Clear Skies").
///
/// Bought with Coins, which come only from rewarded video — so this can only
/// ever suppress *involuntary* ads: the game-over interstitial and the app-open
/// ad. Rewarded video is never suppressed. It is the only faucet, and a player
/// who could switch it off could spend their way into an economy with no income
/// and no way back.
///
/// The balance is metered in **game-clock seconds**, not wall-clock: it only
/// drains while a run is actually live. A wall clock would leak value — buy it,
/// close the app, it expires unused — and would sell minutes of the player's
/// life rather than runs of the game. It also makes the offer easy to say out
/// loud: 150 Coins is about your next ten runs, uninterrupted.
class ClearSkiesService {
  ClearSkiesService(this._storage)
    : _seconds = _storage.clearSkiesSeconds.clamp(0.0, double.infinity) {
    _remaining = ValueNotifier(_asDuration);
  }

  /// How much game time to let accumulate before writing to storage.
  ///
  /// [tick] runs every frame; persisting there would be a prefs write 60 times
  /// a second. Anything unflushed is lost to a force-kill, which is a few
  /// seconds in the player's favour and not worth the I/O to prevent.
  static const _flushEvery = 5.0;

  final StorageService _storage;

  double _seconds;
  double _unflushed = 0;

  late final ValueNotifier<Duration> _remaining;

  /// Whole seconds left, for the HUD. Only changes when the displayed second
  /// does, so a frame-rate ticker does not rebuild the tree 60 times a second.
  ValueListenable<Duration> get remaining => _remaining;

  bool get isActive => _seconds > 0;

  Duration get _asDuration => Duration(seconds: _seconds.floor());

  /// Burns [dt] seconds of balance.
  ///
  /// Called from `TetrofallGame.update`, which Flame does not run while the
  /// engine is paused — and the caller gates on the run actually being in play,
  /// because Flame keeps ticking through the game-over overlay and behind the
  /// main menu's attract-mode demo.
  void tick(double dt) {
    if (_seconds <= 0 || dt <= 0) return;
    final before = _asDuration;
    _seconds = (_seconds - dt).clamp(0.0, double.infinity);
    _unflushed += dt;

    if (_asDuration != before) _remaining.value = _asDuration;
    if (_unflushed >= _flushEvery || _seconds == 0) _flush();
  }

  /// Adds a purchased tier to the balance. Tiers stack rather than replace, so
  /// buying again while one is running is never a downgrade.
  Future<void> grant(Duration gameTime) async {
    _seconds += gameTime.inSeconds;
    _unflushed = 0;
    _remaining.value = _asDuration;
    await _storage.setClearSkiesSeconds(_seconds);
  }

  /// Charges for one suppressed app-open ad.
  ///
  /// App-open ads fire on foregrounding, which is not game time, so
  /// suppressing them would otherwise cost the balance nothing and be free
  /// revenue lost. `AdsService` caps them at one an hour, so this is a handful
  /// of debits a session at most.
  void debitAppOpen() {
    if (_seconds <= 0) return;
    _seconds = (_seconds - EconomyTuning.clearSkiesAppOpenDebit.inSeconds)
        .clamp(0.0, double.infinity);
    _unflushed = 0;
    _remaining.value = _asDuration;
    _flush();
  }

  /// Writes the balance out. Called on a flush threshold, and by the gameplay
  /// screen when a run ends or the app goes to the background.
  void flush() => _flush();

  void _flush() {
    _unflushed = 0;
    _storage.setClearSkiesSeconds(_seconds);
  }

  void dispose() {
    _flush();
    _remaining.dispose();
  }
}
