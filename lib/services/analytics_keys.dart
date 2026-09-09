/// GameAnalytics credentials.
///
/// These are client-side keys — every copy of the game ships with them, the
/// same way [AdUnitIds] ships the AdMob unit ids. They identify the game to
/// GameAnalytics' collection endpoint; they are not a server secret and there
/// is nothing to protect by keeping them out of the repo.
///
/// Both come from the GameAnalytics dashboard under
/// Settings → Game → Game Keys. Leaving either blank turns analytics into a
/// hard no-op ([configured]) rather than shipping a build that talks to
/// somebody else's game.
abstract final class AnalyticsKeys {
  static const gameKey = '29f93eb126eee1311c352409794cfa26';

  static const secretKey = 'b2dc4e199c61d99a411acc4e2150f783cc91cbc5';

  /// Reported to GameAnalytics as the build, so a regression can be pinned to
  /// the release that introduced it. Keep in sync with `pubspec.yaml`'s
  /// `version:` — deliberately a plain constant rather than a `package_info`
  /// lookup, which would be a whole platform channel for one string.
  static const build = '1.0.3';

  static bool get configured => gameKey.isNotEmpty && secretKey.isNotEmpty;
}
