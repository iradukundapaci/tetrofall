/* Google Ad Manager / App Campaigns exit shim.
 *
 * This HTML5 creative path does not support the rich-media ad interface
 * standard some other exchanges use — see playable_ad_plan.md Section 3/6
 * for why that other API must never be loaded or called here. The
 * mechanism this path actually uses is the ExitApi that Google's own
 * harness injects into the page at runtime.
 *
 * Falls back to a console no-op when ExitApi isn't present (e.g. testing
 * this build in a plain desktop browser), so local QA never needs a fake
 * harness stubbed in.
 */
(function () {
  window.TF = window.TF || {};
  TF.exitToStore = function () {
    if (typeof ExitApi !== 'undefined' && typeof ExitApi.exit === 'function') {
      ExitApi.exit();
    } else {
      console.log('[TF] Google shim: ExitApi.exit() not available (not running inside Ad Manager host).');
    }
  };
})();
