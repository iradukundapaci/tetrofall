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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;

    final width = MediaQuery.sizeOf(context).width.truncate();
    // Locked in for the lifetime of this slot: even if the measured size
    // arrives later and differs, the layout must not shift mid-run.
    _slotHeight = widget.ads.reservedBannerHeight(width);
    _load(width);
  }

  Future<void> _load(int width) async {
    await widget.ads.init();
    if (!mounted || !widget.ads.canRequestAds) return;

    final size = await widget.ads.resolveBannerSize(width);
    if (!mounted || size == null) return;

    final ad = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
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

  @override
  void dispose() {
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
