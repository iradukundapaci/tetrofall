/// GameAnalytics client-side keys (Settings → Game → Game Keys); not secrets,
/// every copy of the game ships them. Leaving either blank makes analytics a
/// no-op ([configured]).
abstract final class AnalyticsKeys {
  static const gameKey = '29f93eb126eee1311c352409794cfa26';

  static const secretKey = 'b2dc4e199c61d99a411acc4e2150f783cc91cbc5';

  /// Fallback build tag when `package_info_plus` can't answer. Keep in sync
  /// with `pubspec.yaml`'s `version:`.
  static const build = '1.1.3';

  static bool get configured => gameKey.isNotEmpty && secretKey.isNotEmpty;
}
