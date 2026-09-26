import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_unit_ids.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';

/// Bottom banner slot that always occupies the same height, so the play area
/// never resizes when an ad loads late, fails, or isn't requested.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key, required this.ads, this.bottomInset = 0});

  final AdsService ads;

  /// Bottom safe-area inset to keep clear below the ad; gameplay passes its
  /// leftover slack.
  final double bottomInset;

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  /// Backoff matching [AdsService]'s; the banner owns its own load.
  static const _firstRetry = Duration(seconds: 4);
  static const _maxRetry = Duration(seconds: 60);

  BannerAd? _bannerAd;
  double _slotHeight = 0;
  bool _requested = false;
  int _width = 0;

  Timer? _retryTimer;
  Duration _retryDelay = _firstRetry;

  /// Bumped when a load starts or is abandoned, so a stale banner can tell.
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
    // Locked for the slot's lifetime so the layout never shifts mid-run.
    _slotHeight = widget.ads.reservedBannerHeight(
      _width,
      screenHeight: screen.height,
    );
    _load();
  }

  /// Consent or personalisation changed, so the ad on screen is stale: take it
  /// down and fetch one under the new answer. The slot keeps its height.
  void _onAdConfigChanged() {
    if (!mounted) return;
    setState(() {
      _bannerAd?.dispose();
      _bannerAd = null;
    });
    _resetRetry();
    _load();
  }

  /// Network back, app resumed or consent resolved; only matters to an empty
  /// slot.
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
      // Not necessarily a refusal: consent may not have resolved yet.
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
          // A banner is shown the moment it loads; there is no show step.
          AnalyticsService.ad(
            outcome: AdOutcome.shown,
            kind: AdKind.banner,
            placement: AdPlacements.banner,
          );
          setState(() {
            _bannerAd = ad as BannerAd;
            // An estimated reserve can undershoot on a first-ever cold start;
            // growing once beats clipping. Later runs use the stored height.
            final loaded = ad.size.height.toDouble();
            if (loaded > _slotHeight) _slotHeight = loaded;
          });
        },
        onAdFailedToLoad: (ad, error) {
          AdsService.reportLoadFailure(
            AdPlacements.banner,
            AdKind.banner,
            error,
          );
          if (identical(ad, _bannerAd) && mounted) {
            setState(() => _bannerAd = null);
          }
          ad.dispose();
          if (_isCurrent(generation)) _scheduleRetry();
        },
        onAdClicked: (_) => widget.ads.notifyAdClicked(),
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
        // Bottom-aligned so reserved slack collects above the ad as board
        // padding, not as a dark band below it.
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
