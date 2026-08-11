import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService(this._prefs);

  static const _bestScoreKey = 'best_score';
  static const _adaptiveStartSpeedKey = 'adaptive_start_speed_enabled';
  static const _musicVolumeKey = 'music_volume';
  static const _sfxVolumeKey = 'sfx_volume';
  static const _musicRestoreLevelKey = 'music_restore_level';
  static const _sfxRestoreLevelKey = 'sfx_restore_level';
  static const _vibrateEnabledKey = 'vibrate_enabled';
  static const _ghostPieceEnabledKey = 'ghost_piece_enabled';
  static const _runsSinceLastInterstitialKey = 'ads_runs_since_interstitial';
  static const _playSecondsSinceLastInterstitialKey =
      'ads_play_seconds_since_interstitial';
  static const _lastAppOpenAdEpochMsKey = 'ads_last_app_open_epoch_ms';
  static const _bannerAdWidthKey = 'ads_banner_width';
  static const _bannerAdHeightKey = 'ads_banner_height';

  final SharedPreferences _prefs;

  static Future<StorageService> load() async {
    return StorageService(await SharedPreferences.getInstance());
  }

  int get bestScore => _prefs.getInt(_bestScoreKey) ?? 0;

  bool get adaptiveStartSpeedEnabled =>
      _prefs.getBool(_adaptiveStartSpeedKey) ?? false;

  /// 0.0–1.0. Defaults match settings.html's mockup sliders (70/85%).
  double get musicVolume => _prefs.getDouble(_musicVolumeKey) ?? 0.70;

  double get sfxVolume => _prefs.getDouble(_sfxVolumeKey) ?? 0.85;

  /// Where the mute button puts the slider back to. Kept out of the volume
  /// itself because muting has to write a zero there, and remembered across
  /// screens so leaving Settings doesn't cost the player their level.
  double get musicRestoreLevel =>
      _prefs.getDouble(_musicRestoreLevelKey) ?? 0.70;

  double get sfxRestoreLevel => _prefs.getDouble(_sfxRestoreLevelKey) ?? 0.85;

  bool get vibrateEnabled => _prefs.getBool(_vibrateEnabledKey) ?? true;

  /// Enabled by default per game.md §1.2.
  bool get ghostPieceEnabled => _prefs.getBool(_ghostPieceEnabledKey) ?? true;

  /// Interstitial frequency cap (phase11_monetization_plan.md §3) — number
  /// of completed runs since the last interstitial was shown.
  int get runsSinceLastInterstitial =>
      _prefs.getInt(_runsSinceLastInterstitialKey) ?? 0;

  /// Cumulative play seconds since the last interstitial was shown.
  double get playSecondsSinceLastInterstitial =>
      _prefs.getDouble(_playSecondsSinceLastInterstitialKey) ?? 0;

  /// Epoch ms of the last app-open ad shown, or null if none yet.
  DateTime? get lastAppOpenAdShownAt {
    final epochMs = _prefs.getInt(_lastAppOpenAdEpochMsKey);
    return epochMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(epochMs);
  }

  /// Last measured anchored-adaptive banner height for a screen [width] in
  /// logical pixels, or null if this device hasn't measured one yet. Lets
  /// gameplay reserve the banner slot on the very first frame of a cold
  /// start instead of resizing the board when the ad arrives.
  int? bannerAdHeightForWidth(int width) =>
      _prefs.getInt(_bannerAdWidthKey) == width
      ? _prefs.getInt(_bannerAdHeightKey)
      : null;

  Future<void> saveBestScore(int value) => _prefs.setInt(_bestScoreKey, value);

  Future<void> saveBannerAdSize({
    required int width,
    required int height,
  }) async {
    await _prefs.setInt(_bannerAdWidthKey, width);
    await _prefs.setInt(_bannerAdHeightKey, height);
  }

  Future<void> saveAdaptiveStartSpeedEnabled(bool value) =>
      _prefs.setBool(_adaptiveStartSpeedKey, value);

  Future<void> saveMusicVolume(double value) =>
      _prefs.setDouble(_musicVolumeKey, value);

  Future<void> saveSfxVolume(double value) =>
      _prefs.setDouble(_sfxVolumeKey, value);

  Future<void> saveMusicRestoreLevel(double value) =>
      _prefs.setDouble(_musicRestoreLevelKey, value);

  Future<void> saveSfxRestoreLevel(double value) =>
      _prefs.setDouble(_sfxRestoreLevelKey, value);

  Future<void> saveVibrateEnabled(bool value) =>
      _prefs.setBool(_vibrateEnabledKey, value);

  Future<void> saveGhostPieceEnabled(bool value) =>
      _prefs.setBool(_ghostPieceEnabledKey, value);

  Future<void> saveRunsSinceLastInterstitial(int value) =>
      _prefs.setInt(_runsSinceLastInterstitialKey, value);

  Future<void> savePlaySecondsSinceLastInterstitial(double value) =>
      _prefs.setDouble(_playSecondsSinceLastInterstitialKey, value);

  Future<void> saveLastAppOpenAdShownAt(DateTime value) =>
      _prefs.setInt(_lastAppOpenAdEpochMsKey, value.millisecondsSinceEpoch);
}
