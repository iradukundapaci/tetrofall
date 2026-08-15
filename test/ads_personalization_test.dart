import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/services/ads_service.dart';
import 'package:tetrofall/services/storage_service.dart';

/// Covers the personalisation switch without touching the ad SDK: consent has
/// never been granted in these tests, so every load path no-ops and what is
/// left is exactly the logic this file cares about — what goes out on a
/// request, and what the rest of the app is told when that changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdsService ads;
  late StorageService storage;

  Future<void> boot({bool? personalized}) async {
    SharedPreferences.setMockInitialValues({
      'ads_personalized_enabled': ?personalized,
    });
    storage = await StorageService.load();
    ads = AdsService(storage);
  }

  test('personalisation is on for a player who has never touched it', () async {
    await boot();

    expect(ads.personalizedAds, isTrue);
    // Null, not false: false is not a request *for* personalisation, and
    // leaving the field unset is what keeps the UMP answer authoritative.
    expect(ads.adRequest.nonPersonalizedAds, isNull);
  });

  test('turning it off sends npa=1 on every subsequent request', () async {
    await boot();

    await ads.setPersonalizedAds(false);

    expect(ads.personalizedAds, isFalse);
    expect(ads.adRequest.nonPersonalizedAds, isTrue);
  });

  test('the choice survives a restart', () async {
    await boot();
    await ads.setPersonalizedAds(false);

    // Same prefs, new service — the cold start a player gets tomorrow.
    final restarted = AdsService(await StorageService.load());

    expect(restarted.personalizedAds, isFalse);
    expect(restarted.adRequest.nonPersonalizedAds, isTrue);
  });

  test('turning it back on drops the restriction again', () async {
    await boot(personalized: false);
    expect(ads.adRequest.nonPersonalizedAds, isTrue);

    await ads.setPersonalizedAds(true);

    expect(ads.adRequest.nonPersonalizedAds, isNull);
    expect(storage.personalizedAdsEnabled, isTrue);
  });

  test('a change bumps the revision, so live ads are replaced', () async {
    await boot();
    final revisions = <int>[];
    ads.adConfigRevision.addListener(() {
      revisions.add(ads.adConfigRevision.value);
    });

    await ads.setPersonalizedAds(false);
    // Setting it to what it already is changes nothing, so the banner must
    // not tear down and re-request an identical ad.
    await ads.setPersonalizedAds(false);
    await ads.setPersonalizedAds(true);

    expect(revisions, [1, 2]);
  });
}
