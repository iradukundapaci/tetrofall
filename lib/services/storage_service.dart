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
  static const _tutorialSeenKey = 'tutorial_seen';
  static const _runsSinceLastInterstitialKey = 'ads_runs_since_interstitial';
  static const _playSecondsSinceLastInterstitialKey =
      'ads_play_seconds_since_interstitial';
  static const _lastAppOpenAdEpochMsKey = 'ads_last_app_open_epoch_ms';
  static const _bannerAdWidthKey = 'ads_banner_width';
  static const _bannerAdHeightKey = 'ads_banner_height';
  static const _personalizedAdsKey = 'ads_personalized_enabled';

  // Boosters (`boosters.md` §3.8).
  static const _boosterLastLoadoutKey = 'booster_last_loadout';
  static const _boosterRunsCompletedKey = 'booster_runs_completed';

  // Coin economy. Rewarded video is the only faucet; see `EconomyTuning`.
  static const _coinBalanceKey = 'coin_balance';
  static const _boosterChargesKey = 'booster_charges';
  static const _ownedThemesKey = 'owned_themes';
  static const _equippedThemeKey = 'equipped_theme';
  static const _clearSkiesSecondsKey = 'clear_skies_seconds';
  static const _dailyStreakDayKey = 'daily_streak_day';
  static const _dailyLastClaimEpochKey = 'daily_last_claim_epoch';
  static const _dailyChallengeStateKey = 'daily_challenge_state';
  static const _adViewsTodayKey = 'ad_views_today';
  static const _adViewsDayEpochKey = 'ad_views_day_epoch';
  static const _chestSinceBonusKey = 'chest_since_bonus';
  static const _starterGrantGivenKey = 'starter_grant_given';

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

  /// Whether the first-run tutorial has already been shown. Written the moment
  /// it starts rather than when it ends, so quitting or force-killing halfway
  /// through does not queue it up all over again.
  ///
  /// The fallback covers players updating into this build: anyone who already
  /// has a score has already learned the game the hard way, and must not be
  /// dragged back through a tutorial for it.
  bool get tutorialSeen =>
      _prefs.getBool(_tutorialSeenKey) ??
      (_prefs.getInt(_bestScoreKey) ?? 0) > 0;

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

  /// Whether the player lets their ads be personalised. On by default, and
  /// that default is not a decision this switch makes on anyone's behalf:
  /// where UMP governs (the EEA/UK and the regulated US states) the consent
  /// form is still the gate, and this can only narrow what it allowed;
  /// everywhere else personalised is what the AdMob SDK does anyway. The
  /// switch exists so there is a way to turn it off — see
  /// `AdsService.setPersonalizedAds`.
  bool get personalizedAdsEnabled =>
      _prefs.getBool(_personalizedAdsKey) ?? true;

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

  Future<void> saveTutorialSeen(bool value) =>
      _prefs.setBool(_tutorialSeenKey, value);

  Future<void> saveRunsSinceLastInterstitial(int value) =>
      _prefs.setInt(_runsSinceLastInterstitialKey, value);

  Future<void> savePlaySecondsSinceLastInterstitial(double value) =>
      _prefs.setDouble(_playSecondsSinceLastInterstitialKey, value);

  Future<void> saveLastAppOpenAdShownAt(DateTime value) =>
      _prefs.setInt(_lastAppOpenAdEpochMsKey, value.millisecondsSinceEpoch);

  Future<void> savePersonalizedAdsEnabled(bool value) =>
      _prefs.setBool(_personalizedAdsKey, value);

  /// The loadout the last run was played with, as "hammer,drill,..." — what
  /// "Same boosters" replays (§3.7). A corrupted or unknown id falls back to a
  /// fresh roll, which [Loadout.decode] handles by returning null.
  String? get boosterLastLoadout => _prefs.getString(_boosterLastLoadoutKey);

  Future<void> setBoosterLastLoadout(String value) =>
      _prefs.setString(_boosterLastLoadoutKey, value);

  /// Runs finished since the tutorial. Drives the starter kit (§3.6).
  int get boosterRunsCompleted => _prefs.getInt(_boosterRunsCompletedKey) ?? 0;

  Future<void> setBoosterRunsCompleted(int value) =>
      _prefs.setInt(_boosterRunsCompletedKey, value);

  // --- Coin economy -------------------------------------------------------

  /// Coin balance. Plain prefs, exactly like [bestScore], so it is editable on
  /// a rooted device. Accepted deliberately: no real money is at stake, and a
  /// player who cheats their own wallet has only spoiled their own game.
  int get coinBalance => _prefs.getInt(_coinBalanceKey) ?? 0;

  Future<void> setCoinBalance(int value) =>
      _prefs.setInt(_coinBalanceKey, value);

  /// Owned booster charges, encoded "hammer:2,drill:1" — the same comma style
  /// as [boosterLastLoadout]. Unknown or malformed ids are dropped on decode.
  String? get boosterCharges => _prefs.getString(_boosterChargesKey);

  Future<void> setBoosterCharges(String value) =>
      _prefs.setString(_boosterChargesKey, value);

  /// Theme ids the player owns, comma-joined. `classicWood` is free and always
  /// owned, so it is never written here.
  String? get ownedThemes => _prefs.getString(_ownedThemesKey);

  Future<void> setOwnedThemes(String value) =>
      _prefs.setString(_ownedThemesKey, value);

  String? get equippedTheme => _prefs.getString(_equippedThemeKey);

  Future<void> setEquippedTheme(String value) =>
      _prefs.setString(_equippedThemeKey, value);

  /// Remaining Clear Skies balance in *game-clock* seconds. It only drains
  /// while a run is actually live — see `ClearSkiesService`.
  double get clearSkiesSeconds => _prefs.getDouble(_clearSkiesSecondsKey) ?? 0;

  Future<void> setClearSkiesSeconds(double value) =>
      _prefs.setDouble(_clearSkiesSecondsKey, value);

  /// How far into the 7-day login calendar the player is, 0 when unstarted.
  int get dailyStreakDay => _prefs.getInt(_dailyStreakDayKey) ?? 0;

  Future<void> setDailyStreakDay(int value) =>
      _prefs.setInt(_dailyStreakDayKey, value);

  /// When the login reward was last claimed, or null if never. Used to decide
  /// whether the streak advances or resets.
  DateTime? get dailyLastClaimAt {
    final epochMs = _prefs.getInt(_dailyLastClaimEpochKey);
    return epochMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(epochMs);
  }

  Future<void> setDailyLastClaimAt(DateTime value) =>
      _prefs.setInt(_dailyLastClaimEpochKey, value.millisecondsSinceEpoch);

  /// Today's challenge set and progress, opaque to this class.
  String? get dailyChallengeState =>
      _prefs.getString(_dailyChallengeStateKey);

  Future<void> setDailyChallengeState(String value) =>
      _prefs.setString(_dailyChallengeStateKey, value);

  /// Rewarded views taken today. Drives the earn taper in `EconomyTuning`;
  /// only meaningful alongside [adViewsDayEpoch].
  int get adViewsToday => _prefs.getInt(_adViewsTodayKey) ?? 0;

  Future<void> setAdViewsToday(int value) =>
      _prefs.setInt(_adViewsTodayKey, value);

  /// Local-midnight epoch ms that the [adViewsToday] tally belongs to. Stored
  /// rather than derived so the taper survives a restart without resetting.
  int get adViewsDayEpoch => _prefs.getInt(_adViewsDayEpochKey) ?? 0;

  Future<void> setAdViewsDayEpoch(int value) =>
      _prefs.setInt(_adViewsDayEpochKey, value);

  /// Chests opened since the last guaranteed non-Coin reward (the pity rule).
  int get chestsSinceBonus => _prefs.getInt(_chestSinceBonusKey) ?? 0;

  Future<void> setChestsSinceBonus(int value) =>
      _prefs.setInt(_chestSinceBonusKey, value);

  /// Whether the one-off first-launch Coin grant has been paid.
  bool get starterGrantGiven =>
      _prefs.getBool(_starterGrantGivenKey) ?? false;

  Future<void> setStarterGrantGiven(bool value) =>
      _prefs.setBool(_starterGrantGivenKey, value);
}
