import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_unit_ids.dart';
import '../../services/ads_service.dart';

/// Bottom banner slot that always occupies the same height, so the play
/// area above it never resizes when an ad loads late, fails to load, or
/// isn't requested at all.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key, required this.ads});

  final AdsService ads;

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _bannerAd;
  double _slotHeight = 0;
  bool _requested = false;
  int _width = 0;

  /// Bumped every time a load is started or abandoned, so a banner that
  /// arrives after its request stopped being the current one can tell.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.ads.adConfigRevision.addListener(_onAdConfigChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;

    _width = MediaQuery.sizeOf(context).width.truncate();
    // Locked in for the lifetime of this slot: even if the measured size
    // arrives later and differs, the layout must not shift mid-run.
    _slotHeight = widget.ads.reservedBannerHeight(_width);
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
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    await widget.ads.init();
    if (!_isCurrent(generation) || !widget.ads.canRequestAds) return;

    final size = await widget.ads.resolveBannerSize(_width);
    if (!_isCurrent(generation) || size == null) return;

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
          setState(() => _bannerAd = ad as BannerAd);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    ad.load();
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  @override
  void dispose() {
    widget.ads.adConfigRevision.removeListener(_onAdConfigChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    return SizedBox(
      width: double.infinity,
      height: _slotHeight,
      child: ad == null
          ? null
          : Center(
              child: SizedBox(
                width: ad.size.width.toDouble(),
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ),
    );
  }
}
