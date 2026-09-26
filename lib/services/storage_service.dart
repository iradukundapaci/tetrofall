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
  static const _installDateKey = 'install_date_ms';
  static const _sessionCountKey = 'session_count';
  static const _endlessRunCountKey = 'endless_run_count';
  static const _directorSkillKey = 'director_skill';
  static const _quickDeathStreakKey = 'quick_death_streak';
  static const _recentScoresKey = 'recent_scores';
  static const _reviewRequestTimesKey = 'review_request_times';

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
      _prefs.getBool(_tutorialSeenKey) ?? (_prefs.getInt(_bestScoreKey) ?? 0) > 0;

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

  /// When this install first ran. Set once, at first launch of a build that
  /// knows about it: a player updating into it is treated as installed *now*,
  /// which errs on the side of asking for a rating late rather than early.
  DateTime? get installDate {
    final epochMs = _prefs.getInt(_installDateKey);
    return epochMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(epochMs);
  }

  Future<void> ensureInstallDate([DateTime? now]) async {
    if (_prefs.containsKey(_installDateKey)) return;
    await _prefs.setInt(
      _installDateKey,
      (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  int daysSinceInstall([DateTime? now]) {
    final installed = installDate;
    if (installed == null) return 0;
    return (now ?? DateTime.now()).difference(installed).inDays;
  }

  /// App launches so far, counting the current one once it has begun.
  int get sessionCount => _prefs.getInt(_sessionCountKey) ?? 0;

  Future<int> incrementSessionCount() async {
    final next = sessionCount + 1;
    await _prefs.setInt(_sessionCountKey, next);
    return next;
  }

  /// Endless runs started, for the gentler first runs.
  int get endlessRunCount => _prefs.getInt(_endlessRunCountKey) ?? 0;

  Future<void> incrementEndlessRunCount() =>
      _prefs.setInt(_endlessRunCountKey, endlessRunCount + 1);

  /// The Director's long-run estimate of how well the player plays, 0–1.
  double get directorSkill => _prefs.getDouble(_directorSkillKey) ?? 0.2;

  Future<void> saveDirectorSkill(double value) =>
      _prefs.setDouble(_directorSkillKey, value);

  /// Consecutive endless runs that ended in under a minute.
  int get quickDeathStreak => _prefs.getInt(_quickDeathStreakKey) ?? 0;

  Future<void> saveQuickDeathStreak(int value) =>
      _prefs.setInt(_quickDeathStreakKey, value);

  /// Scores of the last few finished endless runs, oldest first.
  List<int> get recentScores => [
    for (final s in _prefs.getStringList(_recentScoresKey) ?? const <String>[])
      ?int.tryParse(s),
  ];

  static const _recentScoresKept = 10;

  Future<void> addRecentScore(int score) {
    final scores = [...recentScores, score];
    final kept = scores.length > _recentScoresKept
        ? scores.sublist(scores.length - _recentScoresKept)
        : scores;
    return _prefs.setStringList(_recentScoresKey, [
      for (final s in kept) '$s',
    ]);
  }

  /// When the store's rating prompt was last requested, newest last.
  List<DateTime> get reviewRequestTimes => [
    for (final s
        in _prefs.getStringList(_reviewRequestTimesKey) ?? const <String>[])
      ?_epochOrNull(s),
  ];

  static DateTime? _epochOrNull(String s) {
    final ms = int.tryParse(s);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> addReviewRequest(DateTime when) {
    final times = [...reviewRequestTimes, when];
    return _prefs.setStringList(_reviewRequestTimesKey, [
      for (final t in times) '${t.millisecondsSinceEpoch}',
    ]);
  }
}
