import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tetrofall/services/ads_service.dart';
import 'package:tetrofall/services/connectivity_service.dart';
import 'package:tetrofall/services/storage_service.dart';

/// Covers the recovery a start with no internet depends on.
///
/// Consent is stubbed out at [ConsentInformation.instance], and every case
/// leaves `canRequestAds` false unless it says otherwise — so the ad SDK is
/// never reached and what is left is exactly the question this file is about:
/// does a startup that failed for want of a network get tried again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeConsentInformation consent;
  late StreamController<List<ConnectivityResult>> changes;
  late ConnectivityService connectivity;
  late AdsService ads;
  late bool reachable;
  late int sizeMeasurements;

  final realConsent = ConsentInformation.instance;

  /// The one part of the consent flow that isn't reachable through
  /// [ConsentInformation.instance]: showing the form goes straight to the
  /// platform channel. It takes no arguments and returns nothing, so a
  /// handler that answers null is a complete stand-in for "no form to show".
  const umpChannel = MethodChannel('plugins.flutter.io/google_mobile_ads/ump');

  /// The ad SDK's own channel. Nothing here wants a working SDK — the one
  /// case that gets as far as consent granted still has to survive the
  /// handshake, and answering null is the "no SDK on this platform" reply
  /// that [AdsService] is expected to shrug off and retry later.
  const adsChannel = MethodChannel('plugins.flutter.io/google_mobile_ads');

  setUp(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(umpChannel, (_) async => null);
    sizeMeasurements = 0;
    messenger.setMockMethodCallHandler(adsChannel, (call) async {
      if (call.method.startsWith('AdSize#get')) sizeMeasurements++;
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    consent = _FakeConsentInformation();
    ConsentInformation.instance = consent;

    reachable = false;
    changes = StreamController<List<ConnectivityResult>>.broadcast();
    connectivity = ConnectivityService(
      changes: changes.stream,
      probe: () async => reachable,
    );
    ads = AdsService(await StorageService.load(), connectivity: connectivity);
  });

  tearDown(() {
    ads.dispose();
    connectivity.dispose();
    unawaited(changes.close());
    ConsentInformation.instance = realConsent;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(umpChannel, null);
    messenger.setMockMethodCallHandler(adsChannel, null);
  });

  /// Lets the connectivity probe, its listeners, and the consent round trip
  /// they kick off all settle. Several hops deep, so drain rather than pump.
  Future<void> settle() => pumpEventQueue();

  test('a start with no internet finishes without asking UMP', () async {
    await ads.init();
    await settle();

    // The request would only have failed, and a failure is what used to be
    // mistaken for a refusal for the rest of the session.
    expect(consent.updateRequests, 0);
    expect(ads.canRequestAds, isFalse);
  });

  test('init() completes offline rather than waiting for a network', () async {
    // The banner and Settings both await this; hanging here would stall them
    // for as long as the player stayed offline.
    await ads.init().timeout(const Duration(seconds: 1));
  });

  test('the network arriving asks UMP for the first time', () async {
    await ads.init();
    await settle();
    expect(consent.updateRequests, 0);

    reachable = true;
    changes.add([ConnectivityResult.wifi]);
    await settle();

    expect(consent.updateRequests, 1);
  });

  test('consent that arrives late turns ads on and says so', () async {
    consent.allowAds = true;
    await ads.init();
    await settle();
    expect(ads.canRequestAds, isFalse);

    var pulses = 0;
    ads.adRetryPulse.addListener(() => pulses++);

    reachable = true;
    changes.add([ConnectivityResult.wifi]);
    await settle();

    expect(ads.canRequestAds, isTrue);
    // The banner has already given up and Settings has already drawn its
    // Privacy rows; the pulse is the only thing that tells them otherwise.
    expect(pulses, greaterThan(0));
  });

  test('a UMP failure is retried, a UMP answer is not re-asked', () async {
    consent.succeed = false;
    reachable = true;
    connectivity.refresh();
    await settle();
    await ads.init();
    await settle();
    expect(consent.updateRequests, 1, reason: 'asked, and failed');

    // Second chance: the network flapped, so ask again.
    changes.add([ConnectivityResult.none]);
    await settle();
    changes.add([ConnectivityResult.wifi]);
    await settle();
    expect(consent.updateRequests, 2);

    // This one answers. After that the question is settled and further
    // triggers must not re-open the consent flow at the player.
    consent.succeed = true;
    changes.add([ConnectivityResult.none]);
    await settle();
    changes.add([ConnectivityResult.wifi]);
    await settle();
    expect(consent.updateRequests, 3);

    changes.add([ConnectivityResult.none]);
    await settle();
    changes.add([ConnectivityResult.wifi]);
    await settle();
    expect(consent.updateRequests, 3, reason: 'already answered');
  });

  test('a banner size that could not be measured is not cached', () async {
    // Measuring goes to the SDK, which the mock above answers null to — the
    // same answer a device gives before the SDK has come up. Caching that
    // null used to leave the banner unable to size itself for this width for
    // the rest of the session, so the slot could retry forever and never
    // get past it.
    expect(await ads.resolveBannerSize(360), isNull);
    expect(sizeMeasurements, 1);

    expect(await ads.resolveBannerSize(360), isNull);
    expect(sizeMeasurements, 2, reason: 'asked again rather than remembered');
  });

  test('resuming the app re-probes the network', () async {
    await ads.init();
    await settle();
    expect(connectivity.isOnline.value, isFalse);

    // The player switched wifi on from the notification shade and came back,
    // which on some platforms produces no connectivity event at all.
    reachable = true;
    consent.allowAds = true;
    _sendLifecycleState(AppLifecycleState.resumed);
    await settle();

    expect(connectivity.isOnline.value, isTrue);
    expect(ads.canRequestAds, isTrue);
  });
}

void _sendLifecycleState(AppLifecycleState state) {
  TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
}

class _FakeConsentInformation implements ConsentInformation {
  int updateRequests = 0;
  bool succeed = true;
  bool allowAds = false;

  @override
  void requestConsentInfoUpdate(
    ConsentRequestParameters params,
    OnConsentInfoUpdateSuccessListener successListener,
    OnConsentInfoUpdateFailureListener failureListener,
  ) {
    updateRequests++;
    if (succeed) {
      successListener();
    } else {
      failureListener(FormError(errorCode: 2, message: 'no network'));
    }
  }

  @override
  Future<bool> canRequestAds() async => allowAds;

  @override
  Future<PrivacyOptionsRequirementStatus>
  getPrivacyOptionsRequirementStatus() async =>
      PrivacyOptionsRequirementStatus.notRequired;

  @override
  Future<bool> isConsentFormAvailable() async => false;

  @override
  Future<ConsentStatus> getConsentStatus() async => ConsentStatus.notRequired;

  @override
  Future<void> reset() async {}
}
