/* Meta (Audience Network / Ads Manager) exit shim.
 *
 * IMPORTANT — verify before shipping: Meta's playable JS integration point
 * (the exact global/function used for the CTA click-through) is set by
 * Meta's own Playable Ads spec and has historically been exposed as
 * something like window.FbPlayableAd.onCTAClick(). Specs like this get
 * revised independently of this codebase — confirm the current symbol name
 * against Meta's live published Playable Ads guidelines at build time
 * before this shim goes into a real submission (see playable_ad_plan.md,
 * Section 6.3 "Explicit non-assumption"). No rich-media ad interface
 * standard from another exchange is assumed here.
 *
 * Falls back to a console no-op when Meta's harness isn't present, so
 * local QA never needs a fake harness stubbed in.
 */
(function () {
  window.TF = window.TF || {};
  TF.exitToStore = function () {
    if (window.FbPlayableAd && typeof window.FbPlayableAd.onCTAClick === 'function') {
      window.FbPlayableAd.onCTAClick();
    } else {
      console.log('[TF] Meta shim: FbPlayableAd.onCTAClick() not available (not running inside Meta host, or the symbol has changed — re-verify against the current spec).');
    }
  };
})();
