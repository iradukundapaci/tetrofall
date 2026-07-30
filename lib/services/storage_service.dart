import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService(this._prefs);

  static const _bestScoreKey = 'best_score';
  static const _adaptiveStartSpeedKey = 'adaptive_start_speed_enabled';

  final SharedPreferences _prefs;

  static Future<StorageService> load() async {
    return StorageService(await SharedPreferences.getInstance());
  }

  int get bestScore => _prefs.getInt(_bestScoreKey) ?? 0;

  bool get adaptiveStartSpeedEnabled =>
      _prefs.getBool(_adaptiveStartSpeedKey) ?? false;

  Future<void> saveBestScore(int value) => _prefs.setInt(_bestScoreKey, value);

  Future<void> saveAdaptiveStartSpeedEnabled(bool value) =>
      _prefs.setBool(_adaptiveStartSpeedKey, value);
}
