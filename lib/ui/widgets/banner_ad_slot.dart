import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_unit_ids.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';

/// Bottom banner slot that always occupies the same height, so the play
/// area above it never resizes when an ad loads late, fails to load, or
/// isn't requested at all.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key, required this.ads, this.bottomInset = 0});

  final AdsService ads;

  /// Bottom safe-area inset to keep clear *below* the ad. Gameplay passes
  /// whatever vertical slack it has left after sizing the board, so the
  /// banner is held above the home indicator when there is room to spare and
  /// runs edge to edge when there is not.
  final double bottomInset;

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  /// Backoff between attempts, matching the one [AdsService] uses for the
  /// cached formats. The banner needs its own because it owns its own load:
  /// nothing in the service knows this slot exists.
  static const _firstRetry = Duration(seconds: 4);
  static const _maxRetry = Duration(seconds: 60);

  BannerAd? _bannerAd;
  double _slotHeight = 0;
  bool _requested = false;
  int _width = 0;

  Timer? _retryTimer;
  Duration _retryDelay = _firstRetry;

  /// Bumped every time a load is started or abandoned, so a banner that
  /// arrives after its request stopped being the current one can tell.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.ads.adConfigRevision.addListener(_onAdConfigChanged);
    widget.ads.adRetryPulse.addListener(_onRetryPulse);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;

    final screen = MediaQuery.sizeOf(context);
    _width = screen.width.truncate();
    // Locked in for the lifetime of this slot: even if the measured size
    // arrives later and differs, the layout must not shift mid-run.
    _slotHeight = widget.ads.reservedBannerHeight(
      _width,
      screenHeight: screen.height,
    );
    _load();
  }

  /// Consent or the personalisation switch changed while this banner was on
  /// screen, so the ad in it was served under an answer that no longer holds.
  /// Take it down and, if ads are still allowed at all, fetch one under the
  /// new answer. The slot keeps its height throughout, so the board above it
  /// never moves — the same reason the slot exists.
  void _onAdConfigChanged() {
    if (!mounted) return;
    setState(() {
      _bannerAd?.dispose();
      _bannerAd = null;
    });
    _resetRetry();
    _load();
  }

  /// The network came back, the app was resumed, or consent finally resolved.
  /// Only interesting to a slot that has nothing to show — one already
  /// holding an ad has no reason to request another.
  void _onRetryPulse() {
    if (!mounted || !_requested || _bannerAd != null) return;
    _resetRetry();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    await widget.ads.init();
    if (!_isCurrent(generation)) return;

    if (!widget.ads.canRequestAds) {
      // Not necessarily a refusal — consent may simply not have resolved yet,
      // which is what a start with no internet looks like from here.
      _scheduleRetry();
      return;
    }

    final size = await widget.ads.resolveBannerSize(_width);
    if (!_isCurrent(generation)) return;
    if (size == null) {
      _scheduleRetry();
      return;
    }

    final ad = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: size,
      request: widget.ads.adRequest,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!_isCurrent(generation)) {
            ad.dispose();
            return;
          }
          _resetRetry();
          // A banner is on screen the moment it loads — there is no separate
          // show step to hang this off, the way the full-screen formats have.
          AnalyticsService.ad(
            outcome: AdOutcome.shown,
            kind: AdKind.banner,
            placement: AdPlacements.banner,
          );
          setState(() {
            _bannerAd = ad as BannerAd;
            // An *estimated* reserve can undershoot on a first-ever cold
            // start, before this device has measured a banner at all.
            // Growing the slot once beats clipping the ad; from the second
            // run on the height is measured and persisted, so this never
            // fires and the board still never moves mid-run.
            final loaded = ad.size.height.toDouble();
            if (loaded > _slotHeight) _slotHeight = loaded;
          });
        },
        onAdFailedToLoad: (ad, error) {
          AnalyticsService.ad(
            outcome: AdOutcome.failed,
            kind: AdKind.banner,
            placement: AdPlacements.banner,
            reason: error.code == 3 ? AdFailure.noFill : AdFailure.unknown,
          );
          ad.dispose();
          if (_isCurrent(generation)) _scheduleRetry();
        },
      ),
    );
    ad.load();
  }

  void _scheduleRetry() {
    if (_retryTimer != null) return;
    final delay = _retryDelay;
    _retryDelay = delay * 2 > _maxRetry ? _maxRetry : delay * 2;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (mounted && _bannerAd == null) _load();
    });
  }

  void _resetRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDelay = _firstRetry;
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  @override
  void dispose() {
    _retryTimer?.cancel();
    widget.ads.adConfigRevision.removeListener(_onAdConfigChanged);
    widget.ads.adRetryPulse.removeListener(_onRetryPulse);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    return SizedBox(
      width: double.infinity,
      height: _slotHeight + widget.bottomInset,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.bottomInset),
        // Bottom-aligned, not centred. The slot is a *reservation*, and any
        // slack between what was reserved and the ad that actually turned up
        // has to collect above the ad, where it reads as board padding.
        // `Center` split it in two, and the half below the ad showed as a
        // dark band between the banner and the home indicator.
        child: ad == null
            ? null
            : Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: ad.size.width.toDouble(),
                  height: ad.size.height.toDouble(),
                  child: AdWidget(ad: ad),
                ),
              ),
      ),
    );
  }
}
