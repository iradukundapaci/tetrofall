import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService(this._prefs);

  static const _bestScoreKey = 'best_score';
  static const _adaptiveStartSpeedKey = 'adaptive_start_speed_enabled';
  static const _musicVolumeKey = 'music_volume';
  static const _sfxVolumeKey = 'sfx_volume';
  static const _vibrateEnabledKey = 'vibrate_enabled';
  static const _ghostPieceEnabledKey = 'ghost_piece_enabled';

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

  bool get vibrateEnabled => _prefs.getBool(_vibrateEnabledKey) ?? true;

  /// Enabled by default per game.md §1.2.
  bool get ghostPieceEnabled => _prefs.getBool(_ghostPieceEnabledKey) ?? true;

  Future<void> saveBestScore(int value) => _prefs.setInt(_bestScoreKey, value);

  Future<void> saveAdaptiveStartSpeedEnabled(bool value) =>
      _prefs.setBool(_adaptiveStartSpeedKey, value);

  Future<void> saveMusicVolume(double value) =>
      _prefs.setDouble(_musicVolumeKey, value);

  Future<void> saveSfxVolume(double value) =>
      _prefs.setDouble(_sfxVolumeKey, value);

  Future<void> saveVibrateEnabled(bool value) =>
      _prefs.setBool(_vibrateEnabledKey, value);

  Future<void> saveGhostPieceEnabled(bool value) =>
      _prefs.setBool(_ghostPieceEnabledKey, value);
}
