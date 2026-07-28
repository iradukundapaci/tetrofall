import 'package:shared_preferences/shared_preferences.dart';

/// Wraps `shared_preferences` for the handful of values that must survive
/// an app relaunch (improvement.md §8): best score and the coin wallet.
/// Loaded once at app start ([load]) so every read afterward is
/// synchronous — `SharedPreferences` caches values in memory after
/// `getInstance()`, so [bestScore]/[coins] are always up to date even
/// before a pending [saveBestScore]/[saveCoins] write has hit disk.
class StorageService {
  StorageService(this._prefs);

  static const _bestScoreKey = 'best_score';
  static const _coinsKey = 'coins';

  final SharedPreferences _prefs;

  static Future<StorageService> load() async {
    return StorageService(await SharedPreferences.getInstance());
  }

  int get bestScore => _prefs.getInt(_bestScoreKey) ?? 0;
  int get coins => _prefs.getInt(_coinsKey) ?? 0;

  Future<void> saveBestScore(int value) => _prefs.setInt(_bestScoreKey, value);
  Future<void> saveCoins(int value) => _prefs.setInt(_coinsKey, value);
}
