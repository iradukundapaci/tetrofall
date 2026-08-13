# Tetrofall — Android Production Release Plan

Everything needed to take Tetrofall from its current state to a live listing on
Google Play, in dependency order. Each phase is a checkpoint: don't start the
next one until the current one's exit criteria pass.

**Baseline audited on 2026-08-12** (branch `main`, commit `46d7ecf`):

| Thing | State today |
| --- | --- |
| Flutter / Dart | 3.44.8 stable / 3.12.2 |
| Application ID | `com.nosleepstudios.tetrofall` (already set, already namespaced — **final, cannot change after first upload**) |
| Version | `1.0.0+1` in `pubspec.yaml` |
| Launcher icon | ~~❌ Still the stock Flutter blue logo~~ → ✅ **Phase 1 done.** Gold T on a wood plate, legacy + adaptive + monochrome, all densities. Sources in `branding/`, generator in `tools/branding/`. |
| Native splash | ~~❌ plain white~~ → ✅ **Phase 1 done.** `#2B1C12` on both the legacy and the Android 12+ path, `NormalTheme` pinned dark too. |
| App label | ~~❌ lowercase~~ → ✅ **Phase 2 done.** `android:label="Tetrofall"`. |
| Release signing | ~~❌ debug keys~~ → ✅ **Phase 2 done.** Signed `CN=NoSleep Studios` from `~/keystores/tetrofall-upload.jks`; R8 on. Verified on both the APK and the AAB. |
| minSdk / targetSdk | ~~❌ inherited~~ → ✅ **Phase 2 done.** Pinned to 24 / 36. |
| AdMob | ✅ App ID in manifest, real unit IDs behind `kReleaseMode`, UMP consent flow implemented in `ads_service.dart` |
| `app-ads.txt` | ✅ exists at `website/app-ads.txt` — but the site must be publicly live |
| Privacy policy | ✅ authored at `website/privacy.html` — needs a public URL |
| Tests | 7 test files, all currently in-repo |
| Fonts | Nunito + Baloo 2 bundled (OFL) — ❌ no in-app attribution |

Legend: ✅ done · ⚠️ partial · ❌ not started

---

## Phase 0 — Accounts, decisions & long-lead blockers

Start this **first and today**, because two items here have multi-week wall-clock
latency and everything else is worthless without them.

### 0.1 Google Play Developer account
- [ ] Register at <https://play.google.com/console> — **$25 one-time**, non-refundable.
- [ ] Choose account type deliberately:
  - **Personal** — identity verification with a government ID; simplest.
  - **Organization** — requires a **D-U-N-S number** (free but takes **up to 30
    days** to issue via Dun & Bradstreet). Only pick this if "NoSleep Studios"
    is a registered entity and you want it as the public developer name.
- [ ] Complete identity/address verification. Play will not let you publish
      until verification clears.
- [ ] Set the public developer name to **NoSleep Studios** (matches
      `assets/studio-logo.png` and the website branding).
- [ ] Add a developer contact email + the website URL.

> ⛔ **BLOCKER — the 12-tester rule.** Personal developer accounts created after
> 13 Nov 2023 must run a **closed test with at least 12 testers who stay opted in
> continuously for 14 days** before the "Production" track unlocks. This is
> wall-clock time you cannot compress. Start recruiting 12 Google-account emails
> now (Phase 6.2). Verify the exact current requirement in Play Console →
> *Test and release* → the production-access card, since Google adjusts it.

### 0.2 AdMob account linkage
- [ ] Confirm the AdMob publisher `pub-5422471961828877` account is verified and
      has a **payments profile + tax info** filled in (US tax interview even if
      non-US). No payment profile = no revenue, and it takes days to verify.
- [ ] In AdMob → *Apps* → Tetrofall (Android), **link the app to Google Play**.
      This can only be done once the app exists on Play, so it's a Phase 7
      follow-up, but the account setup is now.

### 0.3 Publish the website (blocks two compliance items)
The `website/` directory is complete but must be reachable at a real domain.
- [ ] Pick + register a domain (or use GitHub Pages on the existing
      `iradukundapaci/tetrofall` repo).
- [ ] Deploy `website/` and confirm all of these return 200:
  - `https://<domain>/privacy.html` → needed for the Play listing **and**
    for the AdMob/UMP consent form.
  - `https://<domain>/support.html` → the support URL for the listing.
  - `https://<domain>/app-ads.txt` → must be at the **root** of the domain you
    declare as the developer website in Play, byte-for-byte:
    `google.com, pub-5422471961828877, DIRECT, f08c47fec0942fa0`
- [ ] Update the `Last updated` date in `privacy.html` if content changes.

### 0.4 Decisions to lock now (they cascade)
| Decision | Recommendation | Why it matters |
| --- | --- | --- |
| Target audience age | **13+ / not "primarily children"** | Selecting a child audience triggers Families Policy: no AdMob personalized ads, ad-format restrictions, extra review. |
| Store app name (30 chars) | `Tetrofall` or `Tetrofall: Wood Block Puzzle` | Keyword-bearing suffix helps discovery; 30-char hard limit. |
| Free vs paid | **Free with ads** (already built) | A paid app cannot later become free. |
| In-app purchases | None in v1.0 | If you ever add a "remove ads" IAP you must declare IAP; adding it later is fine. |
| Countries | All, minus any you want excluded | Easily changed later. |

**Exit criteria:** Play account verified, website live and returning 200 on the
three URLs, 12 tester emails collected in a list.

---

## Phase 1 — Brand assets: icons, splash, in-app imagery ✅ implemented 2026-08-13

This is the phase with the most net-new creative work. The app currently ships
Flutter's default icon; that alone is a rejection-adjacent embarrassment.

> **Status.** Everything in 1.1–1.4 that can be done without a physical Android
> device is done and verified; `flutter build apk --debug` compiles the new
> resources. What remains is on-device eyeballing — see
> [Phase 1 — remaining device checks](#phase-1--remaining-device-checks) at the
> end of this section. Three decisions deviate from the draft config above and
> are called out inline as **Deviation**.

### 1.1 Produce the master icon artwork
The brand mark already exists as **code**, not as a raster: `LogoMark`
(`lib/ui/widgets/logo_mark.dart`) draws the T-tetromino out of wood-block cells.
`assets/logo.svg` and `assets/studio-logo.png` are the **studio** wordmark
(1407×768 / 2814×1536), not a square app icon — do not use them as the launcher icon.

Produce these master files (put them in a new `branding/` directory, gitignored
from the build but committed as source):

| File | Size | Content |
| --- | --- | --- |
| `branding/icon_master.png` | 1024×1024 | Full-bleed icon: wood-grain background (`#4A2F1C`→`#7A5230`) + gold-lit T-mark. No transparency, no rounded corners, no drop shadow — Android masks it. |
| `branding/icon_foreground.png` | 1024×1024 | The T-mark **only**, transparent background, drawn inside a **centred 66% safe circle** (≈676px diameter). Anything outside gets clipped by round/squircle masks. |
| `branding/icon_background.png` | 1024×1024 | The wood texture only (or use a flat colour `#4A2F1C`). |
| `branding/icon_monochrome.png` | 1024×1024 | The T-mark as a **solid single-colour silhouette** on transparent, same 66% safe zone. Used by Android 13+ themed icons. |
| `branding/play_icon_512.png` | 512×512 | 32-bit PNG **with alpha**, ≤1MB. The Play Store listing icon. Same art as `icon_master`. |
| `branding/splash_logo.png` | 1152×1152 | Splash mark on transparent; art drawn within the **inner 768×768** (Android 12 clips a splash icon to a 240dp circle with a 160dp inner keyline). |

**How to generate them without a designer:** build a throwaway Flutter page that
renders `LogoMark(cellSize: …)` over a `bg_wood.png` fill at the target size, and
screenshot/`RepaintBoundary.toImage()` it to PNG. `tools/` already exists as a
home for that script. This keeps the icon pixel-identical to the in-app mark.

**Built as `tools/branding/` — not throwaway.** The forge is a permanent,
re-runnable generator rather than a scratch page, because these files have to be
regenerated every time the mark changes:

```bash
flutter test tools/branding/forge_test.dart     # writes every file in branding/
```

- `tools/branding/icon_art.dart` — the drawing. `MarkGeometry` reproduces
  `LogoMark`'s layout exactly (3 cells + 2 gaps wide, gaps at 12.5% of a cell,
  corners at 20%), so the icon can never drift from the in-app mark.
- `tools/branding/forge_test.dart` — the capture harness. It runs under
  `flutter test` rather than as an app so it needs **no device and no desktop
  target** (this project has only `android/` and `ios/`), and it draws through
  the same engine the app draws with.
- It lives in `tools/`, not `test/`, so a bare `flutter test` never runs it.

**Deviation — the icon mark is gold, the splash mark is wood.** `LogoMark`'s
wood tones sit too close to the wood plate behind them to survive a 48px
launcher icon, so `MarkStyle.gold` keeps the identical geometry and light
direction and changes only the fill, plus a soft halo. `splash_logo.png` is
`LogoMark` itself, unmodified — that one has to match what `SplashScreen` draws
a frame later. See `branding/README.md`.

**Deviation — a seventh master, `splash_logo_legacy.png`.** The two Android
splash mechanisms scale a source image differently, and the mark has to land at
the same on-screen size either way (`SplashScreen` draws it at 130dp):
Android 12+ maps the whole 1152px canvas onto a 240dp icon slot (620px of art →
129dp), while pre-12 `flutter_native_splash` treats the source as xxxhdpi and
divides down per density (520px of art → 130dp at every density). One image
cannot satisfy both.

- [x] Master files produced and eyeballed at 48px (the size that actually matters).
- [x] Icon is legible on both a white and a black home-screen wallpaper.

Both checks are answered by **`branding/contact_sheet.png`**, also emitted by
the forge: every masked form of the icon — legacy squircle, adaptive under a
circular mask, Android 13 themed, and the splash mark — at 192/96/48px over a
white and a black wallpaper. It models the real compositing (the 1.5× adaptive
crop *and* the 16% foreground inset), so it shows the shipped icon rather than
the source art. Regenerate and re-eyeball it after any change to the mark.

### 1.2 Wire up the launcher icons ✅

`flutter_launcher_icons: ^0.14.4` is a dev dependency and the config is in
`pubspec.yaml`. Two changes from the draft above:

- **`adaptive_icon_background` is `branding/icon_background.png`, not a flat
  `#4A2F1C`.** The textured plate is the same wood the board is made of, and it
  is what makes the icon read as *this* game rather than a generic brown square.
- **`remove_alpha_ios` dropped** — `ios: false`, so it did nothing.

```bash
dart run flutter_launcher_icons
```

> ⚠️ **The generator insets the foreground by 16%.** It wraps both the
> foreground and the monochrome layer in `<inset android:inset="16%">`, which
> scales them to 68%. Source art already drawn to the 66% safe zone would be
> shrunk *twice*, landing at roughly half the size it should. `forge_test.dart`
> therefore draws the adaptive mark at **0.608** of the canvas (623px), which
> ships as 623 × 0.68 = 424px — 62% of the visible 72dp viewport, with its
> half-diagonal (253px) clearing the 341px safe radius. If you ever change the
> generator or its version, re-check this number.

- [x] Verify it wrote `mipmap-anydpi-v26/ic_launcher.xml`, the
      `drawable-*/ic_launcher_foreground.png` / `_background` / `_monochrome`
      sets at all five densities, and replaced all five
      `mipmap-*/ic_launcher.png` legacy icons.
- [x] Confirm the Flutter blue logo is **gone** — every mipmap hash changed
      (table below), and the 48px mdpi icon renders the gold T on wood.

**Two corrections to the draft's expectations:**

1. **No `ic_launcher_round.xml`, and none is needed.** flutter_launcher_icons
   does not generate round assets at all. On API 26+ the adaptive icon *is* the
   round icon — the launcher applies the circular mask to the same layers. Only
   API 24–25 would use a separate `android:roundIcon`, and there the launcher
   falls back to circle-cropping `ic_launcher.png`, which the contact sheet
   shows holding up fine (the mark sits well inside the crop). Not worth
   hand-maintaining a fifth asset set for ~1% of devices.
2. The foreground/background/monochrome PNGs land in **`drawable-*`**, not
   `mipmap-*`. That is what the generated `mipmap-anydpi-v26/ic_launcher.xml`
   references; it is correct, just not where the draft said to look.

| Mipmap | Stock Flutter (before) | Tetrofall (after) |
| --- | --- | --- |
| `mipmap-mdpi` | `c7c0c018…` | `10258598…` |
| `mipmap-hdpi` | `6a7c8f0d…` | `79249f24…` |
| `mipmap-xhdpi` | `e14aa409…` | `cc11b41e…` |
| `mipmap-xxhdpi` | `4d470bf2…` | `b7d9eeff…` |
| `mipmap-xxxhdpi` | `3c34e1f2…` | `8e451004…` |

- [ ] **Device:** install and check home screen, app drawer, recents card,
      Settings → Apps list, and Android 13 "Themed icons" toggle on.

### 1.3 Native splash screen (kill the white flash) ✅

Today the cold-start sequence is: **white** `launch_background` → dark `#2B1C12`
Dart `SplashScreen`. That white flash reads as a bug.

`flutter_native_splash: ^2.4.8` is a dev dependency and the config is in
`pubspec.yaml`, as drafted except for two things:

- **`image:` is `branding/splash_logo_legacy.png`** and `android_12.image` is
  `branding/splash_logo.png` — the two-source reason is in §1.1.
- **Deviation — `fullscreen: false`, not `true`.** Every screen in the app uses
  `SafeArea` and keeps the status bar. A fullscreen native splash would hide the
  status bar and then hand back a shorter viewport on the first Flutter frame:
  a visible jump, which is the exact class of flicker this section exists to
  kill. Set it to `true` only if the app ever goes immersive.

```bash
dart run flutter_native_splash:create
```

- [x] `drawable/launch_background.xml` and `drawable-v21/` now layer a 1×1
      `#2B1C12` `background.png` (stretched, `gravity="fill"`) under a centred
      `@drawable/splash` — no white anywhere.
- [x] `values-v31/styles.xml` created for the Android 12+ `SplashScreen` API
      (`windowSplashScreenBackground` / `AnimatedIcon` / `IconBackgroundColor`,
      all `#2B1C12`), plus `values-night-v31/`.
- [x] `values-night/styles.xml` checked — the night `LaunchTheme` points at the
      same dark `launch_background`, so it matches rather than inverts.

> 🔧 **Hand-fix applied on top of the generator: `NormalTheme` was still
> white.** All four styles files left `NormalTheme`'s `windowBackground` as
> `?android:colorBackground`, which under the `Theme.Light.NoTitleBar` parent in
> `values/` and `values-v31/` resolves to **white**. `NormalTheme` is the window
> background *behind the Flutter UI*, so a device in light mode could still
> flash white between the native splash and the first Flutter frame — the bug
> this section is about, surviving the fix. All four now point at
> `@color/tetrofall_window_background` (new `values/colors.xml`, `#2B1C12`,
> deliberately not overridden in `values-night` because the app is dark-only).
> Verified to **survive** a re-run of `flutter_native_splash:create` — the
> generator only rewrites the `LaunchTheme` block — but re-grep for
> `?android:colorBackground` after upgrading the package, since nothing
> enforces this.

- [ ] **Device:** cold-boot test on Android 11 **and** Android 12+ (the splash
      mechanism is completely different across that boundary). Force-stop, clear
      from recents, relaunch — there must be **zero** white frames between the
      launcher and the Dart splash. Test in **light mode** too, which is where
      the `NormalTheme` bug above would have shown.
- [ ] **Device:** confirm the native splash hands off seamlessly into
      `SplashScreen`'s drop animation. The maths says the mark lands at 129–130dp
      either side of the handoff against `SplashScreen`'s 130dp; confirm by eye.

### 1.4 In-app imagery gaps ✅

- [x] **One block theme is intentional for v1.0, and nothing ships empty.**
      `ThemeDefinition` has exactly one instance, `classicWood`, and it is a
      hardcoded default parameter on `TetrofallGame`, `BoardComponent` and
      `BoardFrame` — there is **no theme picker, no themes screen, and no
      storage key** for a theme. The type is a seam for later, not an unfinished
      feature, so there is nothing to hide. Gap 15 is therefore not a shipping
      blocker; it is a v1.1 content item. (Store copy must still not claim
      "multiple themes" — see 4.5.)
- [x] **The Settings "Music" row is now hidden when no loops are bundled.**
      `MusicService` already degraded silently — it probes the asset manifest at
      boot and no-ops on a missing track — but the *slider* remained, which is
      the visible half of the defect. `MusicService.hasBundledTracks` now
      exposes the probe result and `settings_screen.dart` builds the row only
      when it is true, resolving late via `warmUp()` if the probe is still in
      flight. Dropping either mp3 into `assets/audio/music/` brings the row back
      with **no code change**; the README there records this.
- [x] **Asset resolution verified — nothing is upscaled.**
  - `bg_wood.png` 1254² — `BoardFrame` deliberately caps its baked copy at
    1024px (`_maxBakedPx`), so the source is always downsampled, never stretched.
  - `tile_classic_wood.png` 500² — `TileCache` bakes per cell size; a 10-column
    board on a 1080px-wide phone needs ~108px per cell.
  - All 35 UI icons are **SVG**, so resolution-independent by construction.
  - Launcher and splash rasters are generated at all five densities from 1024²
    and 1152² masters.

**Exit criteria:** stock Flutter icon eradicated ✅, adaptive + themed icons
render correctly on a physical device ⏳, no white flash on cold start on both
Android 11 and 14 ⏳.

### Phase 1 — remaining device checks

Everything above that can be verified without hardware has been. These four
need a physical Android device and are the only things standing between Phase 1
and its exit criteria. They pair naturally with the Phase 5.3 device matrix.

| # | Check | Where |
| --- | --- | --- |
| 1 | Launcher icon on home screen, app drawer, recents, Settings → Apps | 1.2 |
| 2 | Android 13 "Themed icons" toggle on — monochrome layer renders | 1.2 |
| 3 | Cold boot, zero white frames, on Android 11 **and** 12+, in **light and dark** system mode | 1.3 |
| 4 | Native splash mark → `SplashScreen` mark handoff has no size/position pop | 1.3 |

**Verified without a device:** `flutter build apk --debug` compiles all the new
resources; `flutter analyze` is clean; `branding/contact_sheet.png` answers the
48px and light/dark-wallpaper checks.

> ⚠️ **Pre-existing test failures, not caused by Phase 1.** `flutter test` has
> two reds on `main` as of commit `46d7ecf`, confirmed by re-running with the
> Phase 1 changes stashed:
> - `test/widget_test.dart` — *"A Timer is still pending even after the widget
>   tree was disposed"* (the splash's dust-particle timers outlive the test).
> - `test/gesture_handler_test.dart` — *"a slow drag past the hard-drop distance
>   soft drops instead"* asserts true, gets false.
>
> Phase 5.1's exit criterion is **all tests green**, so these must be fixed
> before the release build. They are unrelated to icons and splash.

---

## Phase 2 — Build configuration & app signing ✅ implemented 2026-08-13

> **Status.** All of 2.1–2.4 implemented and verified against a real
> `flutter build appbundle --release`, which is now signed with the upload key.
> **Two manual follow-ups remain and only you can do them:** back up the
> keystore password to a password manager, and copy the `.jks` to a second
> offline location (§2.1).
>
> One correction worth reading before you trust the old verification step: the
> `keytool -printcert -jarfile` command this plan gives works on the `.aab` but
> **prints nothing for the `.apk`**. See "Verifying the signature" in 2.2.

### 2.1 Generate the upload keystore
```bash
keytool -genkey -v \
  -keystore ~/keystores/tetrofall-upload.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```
Answer the prompts with real values (CN = NoSleep Studios). Use a strong,
**recorded** password.

> 🔐 **Store the keystore and both passwords in a password manager and in one
> offline backup.** With Play App Signing enabled, a lost *upload* key can be
> reset by Google support, but a lost keystore before enrolment means you can
> never update the app under this package name.

✅ **Generated 2026-08-13.**

- [x] Keystore at `~/keystores/tetrofall-upload.jks`, **outside the repo**,
      mode `600`, in a `700` directory. `CN=NoSleep Studios, O=NoSleep Studios`,
      RSA 2048, alias `upload`, valid until 2053-12-29.
- [x] `android/key.properties` written (mode `600`) and confirmed gitignored and
      untracked. `git ls-files` shows no `.jks` and no `key.properties`.
- [ ] **YOURS TO DO — passwords in a password manager.** A single 32-character
      random alphanumeric password is used for both the store and the key. It
      was printed once in the terminal at generation time and is stored nowhere
      else except `android/key.properties` on this machine.
- [ ] **YOURS TO DO — second backup** of the `.jks` on an encrypted drive or a
      separate cloud vault.

> Two deviations from the command above, both deliberate:
>
> - **`-storetype PKCS12`, not `JKS`.** JKS is Sun's proprietary legacy format;
>   keytool now emits a migration warning on every use of it. PKCS12 is the
>   standard, is keytool's default since JDK 9, and is handled identically by
>   AGP and by Play. The `.jks` file extension is kept so it matches every path
>   already written down here.
> - **The DN is `CN=NoSleep Studios, O=NoSleep Studios` only** — no locality,
>   state or country. Those fields are baked into the certificate permanently
>   and Play does not check them, so inventing a city and a country code to fill
>   them would be putting fabricated identity data into the app's permanent
>   signature. Omitting them is valid.
>
> Since nothing has been uploaded to Play yet, this keystore is still
> disposable: if you would rather own a password that never passed through a
> terminal, delete `~/keystores/tetrofall-upload.jks` and
> `android/key.properties` and re-run the `keytool` command yourself
> interactively. After the first upload it is permanent.

### 2.2 Wire signing into Gradle
✅ **Implemented.** `android/app/build.gradle.kts` now loads
`android/key.properties`, and `.gitignore` was extended *before* any secret
could exist. Both stale `// TODO:` comments are gone.

`android/key.properties` is gitignored, so it is not in the repo — copy the
committed template instead, which carries the keytool command and the backup
warning with it:

```bash
cp android/key.properties.example android/key.properties
# then edit in the real passwords
```

**Deviation — a documented fallback instead of a hard failure.** The draft
config assigns the release `signingConfig` unconditionally, which breaks
`flutter run --release` for anyone without the keystore (and breaks it
confusingly, deep in a Gradle stack trace). Instead the release config is only
created when `key.properties` exists; without it the build falls back to the
debug key **and prints a boxed warning** saying the artifact cannot be uploaded
to Play. The risk this trades against — silently shipping a debug-signed
bundle — is closed by the verification step below, which you must run before
every upload.

- [x] Both stale `// TODO:` comments deleted (the applicationId one and the
      signing one).
- [x] `android/app/proguard-rules.pro` created — deliberately empty, with a note
      on which packages to suspect first if R8 breaks something at runtime.
- [x] R8 enabled (`isMinifyEnabled` + `isShrinkResources`) and **verified to
      build**: `flutter build apk --release` and `flutter build appbundle
      --release` both succeed, and `build/app/outputs/mapping/release/` contains
      the mapping. R8 breaking things at *runtime* still needs a device (5.2).

#### Verifying the signature

> ⛔ **`keytool -printcert -jarfile` prints nothing here, and that is not a
> failure — it is the wrong tool.** AGP disables v1/JAR signing when
> `minSdk >= 24`, so this APK is signed with **v2 only** and has no JAR
> signature for `keytool` to read. Trusting its silence would mean shipping
> unverified. Use `apksigner` (Android SDK build-tools) instead:

```bash
$ANDROID_HOME/build-tools/36.0.0/apksigner verify -v --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

Verified today against the current build, with no keystore present:

```
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug   <-- the fallback
```

- [x] The check itself works and correctly identifies the debug key.
- [x] **Re-run after 2.1 — gap 1 is closed.** Both artifacts now carry the
      upload key, and the fallback warning no longer prints:

```
app-release.apk  Signer #1 certificate DN: CN=NoSleep Studios, O=NoSleep Studios
                 Signer #1 certificate SHA-256 digest: 76f7263325ebd51c…
app-release.aab  Owner: CN=NoSleep Studios, O=NoSleep Studios
```

> 🔍 **Why the APK needs `apksigner` but the AAB does not.** An **app bundle is
> still JAR-signed**, so `keytool -printcert -jarfile` works fine on the `.aab`.
> The **APK** is v2-only, so the same command prints nothing there. Since the
> `.aab` is what you upload, `keytool` is enough for the real gate — but check
> the APK with `apksigner`, because that is the artifact you side-load onto test
> devices in Phase 5.3.

### 2.3 Pin SDK levels and harden the manifest
In `defaultConfig`, replace the inherited values with explicit ones:
```kotlin
        minSdk = 24
        targetSdk = 36
```
- [x] **Confirmed 36 is right for an August 2026 submission.** Google's policy
      page states new apps and app updates must target **Android 16 (API 36)**
      from **31 Aug 2026** — 18 days after this was implemented. An extension to
      1 Nov 2026 can be requested in Play Console if needed. Re-check
      Play Console → *Policy status* anyway before you actually submit; this bar
      moves every August.
      ([policy](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en),
      [guide](https://developer.android.com/google/play/requirements/target-sdk))
- [x] `minSdk = 24` (Android 7.0). Verified in the built APK
      (`aapt2 dump badging` → `minSdkVersion:'24'`, `targetSdkVersion:'36'`).
      Both are now **pinned literals** rather than `flutter.minSdkVersion` /
      `flutter.targetSdkVersion`. They happen to equal the Flutter 3.44 defaults
      today, which is exactly why pinning matters: these are a Play compliance
      surface, and a Flutter upgrade must not be able to move them silently.
- [ ] **16 KB page size**: Play requires apps targeting Android 15+ to support
      16 KB memory pages. Flutter 3.44's engine + AGP 8.11 satisfy this, but
      confirm with the Play Console pre-launch report's dedicated check after
      your first upload. *(Nothing to change in code; verification is Phase 6.1.)*
- [ ] **Edge-to-edge**: targeting API 35+ forces edge-to-edge display. Verify the
      gameplay HUD, the banner ad slot (`banner_ad_slot.dart`), and every overlay
      respect `SafeArea` / display cutouts on a notched and a gesture-nav device.

In `android/app/src/main/AndroidManifest.xml`:
```xml
<application
    android:label="Tetrofall"          <!-- was "tetrofall" -->
    ...
    <activity
        android:name=".MainActivity"
        android:screenOrientation="portrait"   <!-- add: matches main.dart, avoids a rotate flash -->
```
- [x] `android:label` is now `Tetrofall`. Verified in the built APK
      (`application-label:'Tetrofall'`).
- [x] `android:screenOrientation="portrait"` added. Verified in the built APK
      (`uses-implied-feature: android.hardware.screen.portrait`).
      Note for later: on Android 16, Play ignores orientation locks on large
      screens (≥600dp), so a tablet will rotate regardless — relevant only if
      you claim tablet support in 4.6.
- [x] **Decided: `android:allowBackup="true"`, stated explicitly** with the
      reasoning in a manifest comment. A player who changes phones keeps their
      best score, and there is no account, secret or server state that would be
      unsafe to restore. It is written out rather than left to the platform
      default so the next person sees a decision, not an accident.
- [x] `INTERNET` / `ACCESS_NETWORK_STATE` left alone — AdMob needs both.
- [x] Confirmed against the built APK: `google_mobile_ads` merges in **six**
      permissions beyond the two above, not just `AD_ID` —
      `com.google.android.gms.permission.AD_ID`, `ACCESS_ADSERVICES_AD_ID`,
      `ACCESS_ADSERVICES_ATTRIBUTION`, `ACCESS_ADSERVICES_TOPICS`, `WAKE_LOCK`
      and `FOREGROUND_SERVICE`. Do not try to remove any of them. The Privacy
      Sandbox ones (`ACCESS_ADSERVICES_*`) reinforce the Phase 3.2 point: the
      Data safety form **must** declare advertising-ID collection.

### 2.4 Versioning policy
`pubspec.yaml`'s `version: 1.0.0+1` drives both `versionName` (`1.0.0`) and
`versionCode` (`1`).
- [x] Shipping v1.0.0 as `1.0.0+1`; verified in the built APK
      (`versionCode='1' versionName='1.0.0'`). Unchanged — `flutter.versionCode`
      / `flutter.versionName` still drive it from `pubspec.yaml`, which is
      correct: pinning those would split the version across two files.
- [ ] **Every** upload to Play — including a re-upload after a rejected internal
      test build — needs a **strictly higher `versionCode`**. Bump the `+N`
      every single time you press upload. Never reuse.
- [ ] Record the mapping (versionCode → git tag) in a table at the bottom of this
      file as you go.

**Exit criteria:** ✅ **all met.** `flutter build appbundle --release` produces
a bundle signed with your upload key ✅, targeting the current
Play-required API level ✅, with the correct app name ✅ and no white splash ✅.

### Phase 2 — what a real build produced

`flutter build appbundle --release` succeeds today, R8 and all:

| | |
| --- | --- |
| Output | `build/app/outputs/bundle/release/app-release.aab`, **58.9 MB** |
| Package | `com.nosleepstudios.tetrofall`, versionCode 1, versionName 1.0.0 |
| SDK | minSdk 24, targetSdk 36, compileSdk 36 |
| Label | `Tetrofall` |
| Signature | APK v2-only, AAB JAR-signed; both `CN=NoSleep Studios` ✅ |
| R8 | ran — `build/app/outputs/mapping/release/mapping.txt` written |

> 📏 **Ignore that 58.9 MB — it is not the download size, and Phase 5.2's "well
> under 40MB" is measured against the wrong number.** An AAB is a *publishing*
> container: Play strips the metadata and serves a per-device split. Breaking
> down what is actually in it:
>
> | Inside the AAB | Size | Ships to users? |
> | --- | --- | --- |
> | `BUNDLE-METADATA/…/proguard.map` | 39.5 MB | ❌ stripped by Play |
> | `BUNDLE-METADATA/…/*.so.sym` (3 ABIs) | ~59 MB | ❌ stripped by Play |
> | `base/lib/arm64-v8a/libflutter.so` | 11.0 MB | ✅ arm64 devices only |
> | `base/lib/arm64-v8a/libapp.so` | ~5.4 MB | ✅ arm64 devices only |
> | `base/lib/{x86_64,armeabi-v7a}/…` | ~25 MB | ✅ *other* ABIs only |
>
> A real arm64 install is the engine + libapp + assets, compressed — an order of
> magnitude under the raw figure. **Judge size from the Play Console's own
> download-size estimate after the first upload (Phase 6.1), not from `ls`.**
>
> Gap 16 is still real but smaller than it looks: 8 of 24 bundled `.ttf` files
> are referenced from `pubspec.yaml`, and `assets/fonts/` is 5.3 MB total, so
> trimming the unused statics and the variable/italic families saves roughly
> 3.5 MB pre-compression — worth doing in 5.2, but it is not what makes this
> number big.

---

## Phase 3 — Legal, privacy & policy compliance ⚠️ code done 2026-08-13, 1 blocker

> **Status.** Everything implementable is implemented: the privacy policy is
> rewritten, the UMP form is re-openable from Settings, and OFL attribution is
> live and covered by a test. The console work (3.2) cannot be done from here,
> so it is written up as a derived answer sheet instead:
> **`branding/store/play-console-answers.md`**. 3.5 is reviewed in
> **`branding/store/trademark-review.md`**.
>
> **One thing blocks submission and it is not code:** the privacy policy's
> **contact email must be a real mailbox** — it is the declared data-deletion
> route, and a bouncing address is a failed one (§3.1, gap 24).
>
> *(Audio licensing — §3.4 — is now cleared: Adobe Firefly, commercial use
> granted on any plan. See `assets/audio/CREDITS.md`.)*
>
> ⚠️ **A correction to 3.2 below:** the claim that the Data safety form "stays
> short" because we ship no analytics **is wrong**, and following it would mean
> under-declaring. See the box in that section.

### 3.1 Privacy policy content check ✅ rewritten

`website/privacy.html` existed but was **inaccurate in the direction that
matters**, claiming collection the app does not do:

> ⛔ **It declared crash reporting and gameplay analytics. The app has neither.**
> There is no Firebase, no Crashlytics, no analytics SDK — Phase 8 still lists
> crash reporting as a *future* consideration. Over-declaring is not the safe
> side of this: the Data safety form must say "no analytics", Play audits the
> form against the policy, and a contradiction between them is a rejection
> cause. Both claims are removed.

It also contradicted a decision made one phase earlier:

> ⛔ **It said data "lives only on your device" and that uninstalling deletes
> everything.** Phase 2.3 set `android:allowBackup="true"`, so settings and the
> high score are copied to the user's own Google Drive and survive a reinstall.
> Now disclosed, with the route to delete the backup.

- [x] Uses **Google AdMob**, and links to
      <https://policies.google.com/technologies/partner-sites>.
- [x] **Advertising ID (AAID)** named explicitly, plus App Set ID.
- [x] Categories now match Google's own SDK disclosure exactly: approximate
      location (from IP), device/other IDs, app interactions, diagnostics.
- [x] Consent management points at the real route — *Settings → Privacy
      Settings* — now that 3.3 has built it.
- [x] Data-deletion route spelled out concretely: uninstall, delete the Drive
      backup, reset the ad ID, or email; 30-day written response.
- [x] Effective date (13 August 2026) and **NoSleep Studios** as developer.
- [ ] ⛔ **`support@nosleepstudios.com` must be a mailbox that receives mail.**
      It appears in the policy, the support page and the footer, and it is the
      declared data-deletion route. If `nosleepstudios.com` will not be
      registered (§0.3 is still open), change it everywhere to an address that
      works. A bouncing contact address is a failed deletion route.

### 3.2 Play Console → App content declarations
Every one of these is mandatory before production. Budget an afternoon.

> 📋 **Answers written up in `branding/store/play-console-answers.md`** —
> derived from the release APK's actual permission list and Google's published
> SDK disclosure, not from memory. Work from that file.
>
> ⛔ **Correction to the bullet below: the form does NOT stay short.** "Declare
> App interactions *if you send any analytics (you currently don't)*" applies the
> wrong test. Per
> [Google's Mobile Ads SDK data disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure),
> **the ad SDK itself collects** IP address, user product interactions,
> diagnostics, the Advertising ID and the App Set ID — whether or not you add
> analytics of your own. Four data types must be declared, not one:
>
> | Category → type | Why |
> | --- | --- |
> | Location → **Approximate location** | Google derives it from the IP. The app holds no location permission — declare it anyway. |
> | App activity → **App interactions** | Collected by the ad SDK. |
> | App info and performance → **Diagnostics** | Collected by the ad SDK. |
> | Device or other IDs | AAID **and** App Set ID. |
>
> All four: collected **and** shared, for advertising + analytics + fraud
> prevention. Declaring only the Advertising ID would be under-declaring, which
> is the thing this section warns gets apps pulled.
- [ ] **Privacy policy URL** — the live `https://<domain>/privacy.html`.
- [ ] **Ads** — declare "Yes, my app contains ads". Non-negotiable.
- [ ] **Data safety form** — declare, at minimum:
  - *Device or other IDs → Advertising ID* — collected, shared with third
    parties, used for Advertising/marketing, **not** user-deletable, not optional.
  - *App activity → App interactions* if you send any analytics (you currently
    don't — keep it that way for v1.0 and the form stays short).
  - Data is encrypted in transit: **Yes** (AdMob uses HTTPS).
  - This form is audited against your actual SDKs. Under-declaring gets the app
    pulled. `google_mobile_ads` **always** means an advertising-ID declaration.
- [ ] **Content rating (IARC) questionnaire** — a falling-block puzzle with ads
      should land at Everyone / PEGI 3. Answer the ads question honestly.
- [ ] **Target audience and content** — select 13+ (see decision 0.4). If you
      select any under-13 bracket you inherit the Families Policy and must
      change the AdMob configuration.
- [ ] **News app**: No. **COVID-19 contact tracing**: No.
- [ ] **Government app**: No. **Financial features**: No.
- [ ] **Data deletion**: provide the contact route from the privacy policy.
- [ ] **App access**: "All functionality is available without special access" —
      there's no login. Say so, or reviewers will bounce it.

### 3.3 Consent (UMP) verification
`AdsService._requestConsent()` already calls `requestConsentInfoUpdate` +
`loadAndShowConsentFormIfRequired`. Before shipping:
- [ ] In the **AdMob Privacy & messaging** console, create and **publish** a GDPR
      consent message for EEA/UK, and a **US states** message if you're
      distributing there. The code is correct but shows nothing if no message is
      published — which means EEA installs serve no personalised ads and revenue
      craters silently.
- [ ] Test with `ConsentDebugSettings` forcing an EEA geography, and confirm the
      form actually appears on a fresh install.
- [ ] Verify graceful behaviour when consent is **denied**: `_canRequestAds`
      goes false, no ads load, and the game is still fully playable — including
      the "continue via rewarded ad" path in `game_over_overlay.dart`, which must
      degrade to a plain game-over rather than hanging.
- [x] **"Privacy Settings" row added** to `settings_screen.dart` under a new
      *PRIVACY & LEGAL* section, using the `shield.svg` icon and a new `_LinkRow`
      built from the existing row shell. It calls
      `AdsService.showPrivacyOptions()`, which wraps
      `ConsentForm.showPrivacyOptionsForm`.

Three things the implementation had to handle that the one-line description
hides:

- **The row is conditional.** It renders only when UMP reports
  `PrivacyOptionsRequirementStatus.required` (exposed as
  `AdsService.privacyOptionsRequired`). Outside the EEA/UK — or before you
  publish the messages in 3.3's first bullet — there is no form to present, so an
  unconditional row would be a button that does nothing, the same defect class as
  the dead music slider closed in 1.4.
- **Consent can now change mid-session, so `_canRequestAds` is no longer
  write-once.** `_refreshConsentState()` re-reads it after the form. Granting
  consent from Settings starts ads for the first time that session
  (`_startAdsIfAllowed`, now idempotent); withdrawing it disposes every cached
  ad, because those were fetched under a choice the user has since revoked.
- **The three `_load*` methods are re-entered from ad-dismissed callbacks**, so
  each now re-checks `_canRequestAds` rather than trusting the boot-time answer.
  Without that, withdrawing consent would stop new ads but silently reload one
  the moment the current ad closed.

### 3.4 Open-source licence attribution
Nunito and Baloo 2 ship under the **SIL Open Font License**, which requires
attribution. `assets/fonts/*/OFL.txt` are in the repo but never surfaced.
- [x] **Registered** in `main()` as `registerFontLicenses()`:
```dart
// in main(), before runApp
LicenseRegistry.addLicense(() async* {
  yield LicenseEntryWithLineBreaks(
    ['Nunito'],
    await rootBundle.loadString('assets/fonts/Nunito/OFL.txt'),
  );
  yield LicenseEntryWithLineBreaks(
    ['Baloo 2'],
    await rootBundle.loadString('assets/fonts/Baloo_2/OFL.txt'),
  );
});
```
- [x] Both `OFL.txt` files added to `assets:` in `pubspec.yaml` and confirmed
      present inside the built APK.
- [x] **"Open source licences"** row added in Settings, calling
      `showLicensePage` with the app name, version and legalese.
- [x] **Covered by a test** — `test/font_licenses_test.dart` asserts both files
      are bundled, contain the OFL text, and actually reach `LicenseRegistry`.
      This is a legal obligation that otherwise fails **silently**: nothing reads
      those assets until a user opens the licence page, so a renamed directory
      would ship as a licence breach with no error. Verified non-vacuous — both
      families are absent from the registry without the registration call.
- [x] **Audio licensing cleared** — recorded in `assets/audio/CREDITS.md`. All
      three `.wav` files were generated with **Adobe Firefly** (Generate Sound
      Effects) from the §P.7 prompts, committed 2026-08-09 in `c13820e`.
      Firefly trains only on Adobe Stock, openly licensed and public domain
      content, and **grants commercial use on the free plan as well as paid** —
      the tiers differ in credits, not rights — with no attribution required.
      This is the route that made it clean: ElevenLabs' free tier is
      non-commercial and Meta's AudioCraft is research-licensed, and either
      would have been a licence breach in an ad-supported release. The one
      caveat that could have bitten — Adobe excludes *beta* output from
      commercial use — does not apply, since Generate Sound Effects was GA well
      before these were made.

### 3.5 Trademark sanity check
- [ ] "Tetris" is an aggressively enforced trademark of the Tetris Company, and
      they routinely file takedowns against falling-block games. **"Tetrofall"
      is close enough to warrant a deliberate look.** Review the store listing,
      icon, and screenshots for anything evoking the Tetris brand (the word
      "Tetris", the classic 7-colour tetromino palette on a cyan/black field, the
      "TETRIS" logo styling). The wood-block art direction already differentiates
      you well — keep it and lean into it in the listing copy.
- [x] **Reviewed in full — see `branding/store/trademark-review.md`.** Verdict:
      proceed with "Tetrofall". The name is the only real exposure; the
      mechanics (rising floor, independent-column cascade) and the wood art
      direction are genuinely differentiating, and the full trade-dress
      checklist is clear — no 7-colour palette, no neon-on-black field, no
      Tetris logo styling, no Korobeiniki. Worth knowing: the *package name* is
      frozen at first upload but the *store display name* is editable any time,
      so a rebrand under complaint would not require republishing as a new app.
- [ ] Do not use the word "Tetris" in the title, description, or keyword fields.
      Including comparative use ("like Tetris but…"), which is both trademark
      use and a Play keyword-policy violation.

**Exit criteria:** every App content section in Play Console shows green ⏳
*(answers ready in `branding/store/play-console-answers.md`; needs an account)*,
the UMP message is published in AdMob ⏳ *(console work)*, licences are
attributed in-app ✅ *(fonts registered and tested; audio cleared)*.

---

## Phase 4 — The Play Store page

This is the whole storefront: the console setup, the copy, and the gameplay
screenshots. It's the part of the release that determines install rate, and it's
worth more care than the build config.

### 4.1 Create the app record

Play Console → **All apps** → **Create app**. You'll be asked for:

| Field | Value | Reversible? |
| --- | --- | --- |
| App name | `Tetrofall: Rising Blocks` (see 4.3) | ✅ editable any time |
| Default language | English (United States) – en-US | ✅ |
| App or game | **Game** | ❌ |
| Free or paid | **Free** | ❌ **A free app can never become paid.** |
| Declarations | Developer Program Policies ✔, US export laws ✔ | — |

- [ ] App record created. The package name isn't chosen here — it's baked into
      your first AAB (`com.nosleepstudios.tetrofall`) and locked forever at that
      moment.

### 4.2 The console task list, in the order it actually unblocks

The dashboard shows a "Set up your app" checklist. Do it in this order; later
items depend on earlier ones and the Production track stays greyed out until
every one is green.

1. **App access** → "All functionality available without restrictions" (no login).
2. **Ads** → Yes, contains ads.
3. **Content rating** → IARC questionnaire (Phase 3.2).
4. **Target audience** → 13+ (Phase 0.4).
5. **News app** → No.
6. **Data safety** → advertising ID declaration (Phase 3.2).
7. **Government apps** → No. **Financial features** → None.
8. **Health apps** → No.
9. **Privacy policy** → live URL (Phase 0.3).
10. **Store settings** → app category **Games → Puzzle**, tags, contact details.
11. **Main store listing** → the copy and graphics below (4.3–4.8).
12. **Select countries and regions**.

- [ ] All 12 green before attempting any track promotion.

### 4.3 App name

The name is the single strongest ranking signal on Play. `Tetrofall` alone is
distinctive but carries zero search weight — nobody types it until they've heard
of it. Add a descriptive suffix. **30-character hard limit, spaces included.**

| Candidate | Chars | Verdict |
| --- | --- | --- |
| `Tetrofall` | 9 | Clean, but invisible in search |
| `Tetrofall: Block Puzzle` | 23 | Safe, generic, high-competition keyword |
| **`Tetrofall: Rising Blocks`** | **24** | ✅ **Recommended** — keyword-bearing *and* it names your actual differentiator |
| `Tetrofall — Wood Block Puzzle` | 29 | Fits, but "wood block puzzle" is a crowded category term |

- [ ] Chosen name is ≤30 chars.
- [ ] Contains no "Tetris", no "#1", no "Free", no "Best", no emoji, no fake
      badges — all are policy violations that get the listing rejected.

### 4.4 Short description (80 chars) ✅ FINAL

> ⚠️ **It is 80 *characters*, not 80 words.** 80 words would be ~500 characters
> and the field will simply reject it. The 4000-character field is 4.5, below.

Shown under the icon in search results and on the listing before the fold. This
is the highest-leverage 80 characters on the page.

**Paste this:**

```text
Blocks fall from above. Rows rise from below. Clear lines or get crushed.
```

**73 / 80 characters.** It states the entire game in two beats and the stakes in
a third. Lead with mechanics, not adjectives.

| Alternative | Chars |
| --- | --- |
| `Falling blocks, rising floor. Clear rows to survive. Offline block puzzle.` | 74 — use if you want the keyword phrase in this field |
| `A wood block puzzle where the stack rises from below. One hand. Offline.` | 72 |
| `The floor rises every few seconds. Clear rows fast or the stack wins.` | 69 |

- [x] Verified ≤80 characters (73) — re-verify after **any** edit.

### 4.5 Full description (4000 chars) ✅ FINAL

Written from the shipped code, and **verified against it on 2026-08-13** — every
number below was read out of the source, not estimated.

> ⛔ **The earlier draft of this section contained two false claims. Both are
> fixed below. Do not paste an older copy.**
>
> | Claim in the old draft | Reality in the build |
> | --- | --- |
> | "A **10x20** board" | `board_config.dart` → `cols = 18; rows = 32;` — nearly triple the area, and a selling point rather than something to shrink |
> | "**Two-finger tap to rotate back**" | **The feature does not exist.** The only rotate call in the whole input path is `GameIntentType.rotateCW` (`gesture_handler.dart:216`), and `onPointerDown` discards a second pointer outright (`if (_pointer != null) return;`). There is no counter-clockwise rotation. |
>
> The second one is the dangerous one: a control instruction that does nothing
> is a guaranteed 1-star review *and* the exact policy breach the checklist
> below warns about. The sentence is removed. If you would rather have the
> feature than lose the line, the engine half already exists —
> `RotationState` has the `index + 3` previous-state accessor — and only the
> gesture is missing.

**Paste this** (1,668 / 4,000 characters):

```text
The blocks fall. The floor fights back.

Tetrofall is a falling-block puzzle with one twist that changes everything: a new row pushes up from the bottom of the board on a timer. You're not just filling a well — you're racing a floor that never stops rising. Clear rows to buy back space. Survive as long as you can.

A CASCADE, NOT A SHIFT
Clear a row in the middle of your stack and the blocks above it don't slide down as one piece. Every block falls independently until it lands on something solid. Columns collapse at different speeds, gaps open where you didn't expect them, and rows finish themselves. Every link in a cascade chain raises your multiplier by another 50%.

THE PRESSURE NEVER LETS UP
• Rows rise every 22 seconds when you start — every 4.5 seconds by minute twelve
• Early rows leave a clustered, forgiving gap; late rows are dense and scattered
• Difficulty interpolates smoothly the whole way — no sudden jumps, no plateau you can memorise
• Beat your best and your next run starts further up the curve

BUILT FOR ONE THUMB
Swipe to move. Tap to rotate. Swipe down to drop. Auto-repeat is tuned for fast play, and a ghost piece shows exactly where your piece will land — leave it on, or switch it off in Settings.

HONEST PUZZLE DESIGN
• All seven pieces, 7-bag randomiser — no droughts, no unwinnable streaks
• Full rotation system with wall kicks
• A big 18x32 board. No lives, no energy meter, no hidden timers
• Warm wood blocks on a wood board, not neon on black
• Plays completely offline — no account, no login, no cloud save required

Easy to learn. Hard to master. Relaxing to play. Satisfying to watch.
One more run.

— NoSleep Studios
```

**What was verified in the source, claim by claim**

| Line | Verified against |
| --- | --- |
| Rows rise every **22s** → **4.5s** by minute twelve | `difficulty.dart` — `riseInterval: 22` at start, `riseInterval: 4.5` at `Duration(minutes: 12)` |
| Every cascade link **+50%** multiplier | `scoring.dart:36` — `final chainMultiplier = 1.0 + 0.5 * chainIndex;` |
| **All seven pieces, 7-bag** | `tetromino.dart:18` — `enum TetrominoType { I, O, T, S, Z, J, L }`; `:241` — `_queue.addAll(TetrominoType.values); _queue.shuffle(_random);` |
| **Wall kicks** | `piece_controller.dart:129` — `Tetromino.kicksFor(p.type, p.rotation, target)` |
| **18x32 board** | `board_config.dart` — `cols = 18; rows = 32;` |
| **Ghost piece toggle** | `tetrofall_game.dart:53` `showGhost`, driven from Settings |
| **Completely offline** | No HTTP client, socket, analytics or crash SDK anywhere in `lib/`; only network-capable plugin is `google_mobile_ads` |

**Rules for editing it:**
- [x] ≤4000 characters (1,668 — plenty of headroom if you want to add).
- [x] First two lines carry the whole pitch — most people never scroll.
- [x] **Never write "Tetris"** (see Phase 3.5) — checked, absent.
- [x] ⚠️ **Nothing promised that isn't in the build.** No "multiple themes"
      (one ships) and no "soundtrack" (`assets/audio/music/` is empty) — gaps 14
      and 15. Re-check this list if either closes.
- [x] Keywords appear naturally: *block puzzle, falling blocks, offline, puzzle,
      one thumb*. No appended keyword list — stuffing is an enforced violation.

> ⚠️ **One open item touching this copy.** The failing
> `gesture_handler_test` — *"a slow drag past the hard-drop distance soft drops
> instead"* (gap 23) — sits directly under the "Swipe down to drop" line. Fix it
> before the copy describing the controls is public.

### 4.6 Graphics spec

| Asset | Spec | Required |
| --- | --- | --- |
| App icon | **512×512**, 32-bit PNG **with alpha**, ≤1MB | ✅ |
| Feature graphic | **1024×500**, PNG or JPG, **no alpha**, ≤15MB | ✅ |
| Phone screenshots | **2–8**, PNG/JPG, 9:16 or 16:9, each side 320–3840px | ✅ (min 2, ship 6–8) |
| 7" tablet screenshots | up to 8 | optional |
| 10" tablet screenshots | up to 8 | optional |
| Promo video | YouTube URL | optional — skip for v1.0 |

Ship phone screenshots at **1080×1920** or **1080×2400**. Never upload a
screenshot with rounded corners baked in, and never upload the icon with a
pre-applied mask — Play applies its own.

Only fill the tablet slots if you actually tested on a tablet (Phase 5.3);
uploading tablet shots claims tablet support and invites tablet reviewers.

### 4.7 Capturing gameplay screenshots

This is the part most indie launches do badly. Screenshot #1 moves install rate
more than every other asset on the page combined, and Play shows the first 2–3
in search results — so shots 1 and 2 must work as a **pair**.

**Step 1 — build a capture mode.** Staging a good board state by playing is
almost impossible; the money shot is three frames long. Add a temporary debug
entry point (a `--dart-define=CAPTURE=true` flag, or a scratch route in `tools/`)
that:
- [ ] force-disables ads, so no banner appears in any shot (`AdsService` already
      gates on `_canRequestAds` — add a capture override);
- [ ] seeds the grid to a hand-authored layout;
- [ ] sets `Scoring.score` and the elapsed clock to chosen values;
- [ ] optionally pauses the animation clock so you can step frame by frame.

Delete or `assert`-gate this before the release build.

**Step 2 — clean the status bar.** Android's demo mode gives you a full battery,
a fixed clock, and zero notification icons:
```bash
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
# ... capture ...
adb shell am broadcast -a com.android.systemui.demo -e command exit
```

**Step 3 — capture at native resolution.** `adb exec-out` writes the raw
framebuffer with no shutter sound and no compression:
```bash
adb exec-out screencap -p > branding/store/shot_01.png
```

**Step 4 — for animation shots, record and extract a frame.** The shatter and
the cascade are the best-looking moments in the game and they're too fast to
catch by hand. Record, then pull the exact frame:
```bash
adb shell screenrecord --bit-rate 16000000 --time-limit 180 /sdcard/run.mp4
adb pull /sdcard/run.mp4 branding/store/
ffmpeg -i branding/store/run.mp4 -vf "select='between(t,42,45)'" -vsync 0 \
  branding/store/frames/%04d.png
```
Then scrub `frames/` and pick the single frame where the shatter particles are
widest and the chain multiplier is on screen.

- [ ] Capture on a **release** build (correct fonts, correct colours, no debug banner).
- [ ] Capture on a 1080×2400 device, portrait, at 100% brightness.
- [ ] **Zero ad slots visible in any screenshot.**

### 4.8 The shot list

Six shots, in upload order. Order is the design — Play reads it left to right.

| # | Screen | What it must show | Caption |
| --- | --- | --- | --- |
| **1** | Gameplay, mid-shatter | A 3–4 row clear exploding center-out, particles at full spread, score visible | **"Clear rows. Watch them shatter."** |
| **2** | Gameplay, mid-cascade | Blocks in free fall at different heights after a middle-row clear, chain indicator lit | **"Blocks fall independently. Chains build themselves."** |
| **3** | Gameplay, rise pressure | Stack near the top, a pending row half-emerged at the bottom edge, board tight | **"The floor rises. Every second counts."** |
| **4** | Gameplay, one-hand controls | Ghost piece outline visible, a piece mid-drop | **"One thumb. Swipe, tap, drop."** |
| **5** | Main menu | Logo mark + wordmark, best score displayed | **"Easy to learn. Hard to master."** |
| **6** | Game over | Final score, best score, crumble effect mid-frame | **"One more run."** |

Shots 1–4 are gameplay. That ratio is deliberate: menu and settings screenshots
convert badly and belong at the end, if at all. Drop shot 5 or 6 before you drop
a gameplay shot.

- [ ] Every shot uses a **different** board state — four near-identical boards
      reads as one screenshot uploaded four times.
- [ ] Score values across shots are plausible and increasing.

### 4.9 Screenshot framing template

Raw captures convert worse than framed ones. Build one 1080×1920 template and
reuse it for all six:

```
┌─────────────────────────┐  1080 × 1920
│  ▓▓ wood texture band   │  ← top 20%: caption on #4A2F1C, gold #F2B632 text,
│  "Clear rows.           │     Baloo 2 ExtraBold, ~72px. Max 5 words.
│   Watch them shatter."  │
├─────────────────────────┤
│                         │
│   ┌───────────────┐     │  ← the device capture, scaled to ~86% width,
│   │  screenshot   │     │     8px gold border, 24px corner radius,
│   │               │     │     soft drop shadow
│   └───────────────┘     │
│                         │
└─────────────────────────┘  ← bottom edge: wood texture continues
```

- [ ] Caption text is legible at **thumbnail size** (test by shrinking to 120px
      wide — if you can't read it, rewrite it shorter).
- [ ] Same band height, same type size, same border on all six.
- [ ] Captions read as a sequence, not six independent slogans.

### 4.10 Feature graphic (1024×500)

Required, and it appears at the top of your listing and in every Play promo
surface — including places where **it plays alone with no screenshots**.

- [ ] Composition: wood-grain background (`bg_wood.png`), the T-mark left of
      centre, "Tetrofall" wordmark in Baloo 2 ExtraBold, a few falling blocks and
      one rising row as visual shorthand for the mechanic.
- [ ] Keep all text and the logo inside the **centre 80%** — the outer margins get
      cropped in some placements.
- [ ] No screenshots inside it, no device frames, no "Download now" call to
      action, no store badges (all are policy violations).
- [ ] Must be legible at 250px wide.

### 4.11 Store settings and listing QA

- [x] Category **Games → Puzzle**. Tags (max 5, chosen from Play's fixed
      vocabulary — pick the nearest match the console offers): **Block Puzzle**
      (highest-traffic exact match), **Brain Games**, **Casual**, **Offline
      Games** (your real differentiator), **Single Player**. Avoid anything
      implying multiplayer or social, and anything about themes or music — the
      build has one theme and no music, so those would overstate it exactly as
      4.5 forbids.
- [ ] Contact email, website `https://<domain>/`, support
      `https://<domain>/support.html`, privacy `https://<domain>/privacy.html`.
- [ ] Preview the listing in the console on **both** the phone and web previews —
      truncation differs between them.
- [ ] Read the full description on a phone-width screen. Anything below the
      "Read more" fold is optional reading; make sure the pitch survives being cut there.
- [ ] Proofread out loud. Typos in the first two lines are the cheapest possible
      credibility loss.
- [x] Final copy saved in this repo — the paste-ready text lives in **4.4 and
      4.5 above**, with per-claim source verification, so the next release edits
      a tracked file rather than a console textarea.

**Exit criteria:** all 12 console checklist items green, six framed screenshots
plus icon and feature graphic uploaded and accepted, listing preview proofread on
phone and web.

---

## Phase 5 — Release-candidate QA

Everything here runs against a **release** build, not debug. Debug builds use
test ad units and a different signature; they prove nothing about production.

### 5.1 Static checks
```bash
flutter clean
flutter pub get
flutter analyze              # must be zero issues
flutter test                 # all 7 suites green
dart format --set-exit-if-changed lib test
```
- [ ] Zero analyzer issues (not "only warnings" — zero).
- [ ] All tests pass.
- [ ] Grep for leftovers: `TODO`, `FIXME`, `print(`, `debugPrint(`, hardcoded
      test ad unit IDs outside `ad_unit_ids.dart`.

### 5.2 Build the App Bundle
```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/symbols/1.0.0+1
```
- [ ] Output at `build/app/outputs/bundle/release/app-release.aab`.
- [ ] **Archive `build/symbols/1.0.0+1/` and keep it forever**, tagged to the
      release. Without it, obfuscated crash stack traces from Play Console are
      unreadable and you deobfuscate with
      `flutter symbolize -i <stack.txt> -d build/symbols/1.0.0+1/app.android-arm64.symbols`.
- [ ] R8 is now on (Phase 2.2). Smoke-test the release build **hard** — R8 is the
      classic source of "works in debug, crashes in release". If ads, audio, or
      `shared_preferences` misbehave only in release, add keep rules to
      `proguard-rules.pro` and re-test.
- [ ] Check the bundle size. A Flutter puzzle game should land well under 40MB;
      if it's larger, look at the 30+ bundled `.ttf` files — you ship both
      variable and full static families for Nunito and Baloo 2 but reference only
      **four weights each** in `pubspec.yaml`. Trimming the unused statics and
      the variable/italic files is easy tens of megabytes.

### 5.3 Device matrix
Test the **release** build (`flutter install --release`, or side-load the APK
built from the same config) on:
- [ ] A small/low-end phone (720×1280, Android 8–10) — check the board scales,
      the HUD isn't clipped, and framerate holds during cascades.
- [ ] A modern phone (1080×2400, Android 14/15) — check edge-to-edge, gesture nav,
      display cutout.
- [ ] A tablet, if you list tablet screenshots.

### 5.4 Functional smoke checklist
- [ ] Cold start: launcher icon → native splash (dark, no flash) → Dart splash
      animation → main menu. No jank, no white frame.
- [ ] Full game loop: play, clear rows, cascade, pause, resume, quit-confirm,
      game over, restart.
- [ ] Every Settings toggle actually does what it says — music, SFX, haptics,
      vibration. (Commit `0cfdb6c` addressed this; re-verify in release.)
- [ ] High score persists across a force-stop **and** an app reinstall-restore.
- [ ] **Ads, with real unit IDs**: register your device as an AdMob **test
      device** so you see real-configuration ads without generating invalid
      traffic. Verify banner, interstitial cadence, rewarded-continue reward
      timing (commits `6462992`/`a232977` touched this — regression-test it), and
      app-open ad on resume.
- [ ] **Airplane mode**: game fully playable, no crash, no infinite spinner, ad
      slots collapse gracefully rather than leaving dead space.
- [ ] Interrupt handling: phone call / notification during play, and backgrounding
      mid-rewarded-ad.
- [ ] Rotate the device — must stay portrait.
- [ ] Back gesture from every screen behaves (no accidental exit mid-game;
      `confirm_quit_overlay.dart` should intercept).

**Exit criteria:** signed release AAB, verified on ≥2 physical devices, symbols
archived, zero known crashes.

---

## Phase 6 — Testing tracks

### 6.1 Internal testing (day 1, up to 100 testers, no review wait)
- [ ] Create the app in Play Console. Fill in the store listing (Phase 4) and all
      App content declarations (Phase 3) — Play blocks track promotion otherwise.
- [ ] Upload the AAB to **Internal testing**. **Opt into Play App Signing** when
      prompted (the default; accept it). Google now holds the app signing key;
      your upload key stays yours.
- [ ] Read the **Pre-launch report** (Play runs the app on real Firebase devices
      automatically). It catches crashes, ANRs, accessibility issues, and the
      16 KB page-size check. Fix anything it flags before promoting.
- [ ] Verify the download from Play installs and runs correctly — this is the
      first time you'll see the **Play-signed** build, which is not byte-identical
      to your local one.

### 6.2 Closed testing — the 14-day gate
- [ ] Create a closed track with an email list of **≥12 testers** (Phase 0.1).
- [ ] Every tester must **accept the opt-in link and install from Play**, and stay
      opted in for **14 consecutive days**. Dropping below 12 restarts the clock.
- [ ] Chase them. This is the single most common cause of a stalled first launch:
      people accept the link and never install.
- [ ] Collect feedback; ship fixes as new versionCodes to the same track (the
      14-day timer tracks tester continuity, not build stability).
- [ ] After 14 days with 12+ testers, apply for **production access** in the
      console and wait for approval (typically days, occasionally longer).

### 6.3 Open testing (optional)
- [ ] Skip for v1.0 unless you want a public beta for reviews/wishlists.

**Exit criteria:** production access granted by Google.

---

## Phase 7 — Production launch

- [ ] Bump `version:` in `pubspec.yaml`, rebuild the AAB, archive the symbols.
- [ ] Create a **Production** release; promote the tested build rather than
      uploading a fresh untested one.
- [ ] Write release notes (500 chars/locale). For v1.0: what the game is, in
      three lines.
- [ ] **Staged rollout — start at 10–20%**, not 100%. If crash-free-users drops or
      1-star reviews spike, you halt the rollout instead of shipping a bad build
      to everyone. Raise to 50% after ~48h clean, then 100%.
- [ ] Set countries/regions.
- [ ] Submit. First-time review commonly takes **up to 7 days**; plan around it.
- [ ] Tag the release in git: `git tag v1.0.0 && git push --tags`.
- [ ] Commit the release plan updates + the version-history table below.

### 7.1 Immediately after going live
- [ ] **Link the app to AdMob** (AdMob → Apps → Tetrofall → *App store* → link to
      the live Play listing). Unlinked apps get restricted ad serving.
- [ ] Verify `app-ads.txt` is crawled: AdMob → *App-ads.txt* status should flip to
      **Authorized** within a few days of the app being live with the developer
      website set. Until then, programmatic demand is throttled.
- [ ] Add the Play listing URL to `website/index.html` and the README.
- [ ] Turn on Play Console email alerts for crashes/ANRs.

### 7.2 First-week watch list
- [ ] **Android vitals**: crash-free sessions (target >99%), ANR rate (must stay
      under Play's 0.47% bad-behaviour threshold or you get demoted in ranking).
- [ ] AdMob: fill rate, eCPM, and whether EEA traffic is showing ads at all
      (a consent-form misconfiguration shows up as near-zero EEA revenue).
- [ ] Reviews — reply to the first ones; early response rate visibly affects
      rating trajectory.
- [ ] Retention/uninstall rate in the console.

---

## Phase 8 — Post-launch hygiene

- [ ] Keep a `CHANGELOG.md`; every Play release gets a versionCode + git tag.
- [ ] Set a calendar reminder each **August** for the Play target-API bump — it's
      an annual hard deadline and apps that miss it stop being discoverable to
      new users.
- [ ] Re-check the Data safety form whenever you add a dependency. Adding
      analytics, crash reporting, or an IAP all require form updates *before* the
      release ships.
- [ ] Consider adding crash reporting (Firebase Crashlytics or Sentry) in 1.1 —
      Play's vitals are aggregated and lag; you'll want real stack traces. Note it
      changes the Data safety declaration.
- [ ] Consider an in-app review prompt (`in_app_review`) after a good run —
      cheapest possible rating lift.

---

## Consolidated gap list (what's actually broken today)

Ordered by blocking severity. Anything ❌ prevents shipping.

| # | Gap | Phase | Severity |
| --- | --- | --- | --- |
| 1 | ~~Release build signed with **debug** keys~~ | 2.1 | ✅ Closed 2026-08-13 — signed `CN=NoSleep Studios` |
| 2 | ~~Launcher icon is the stock Flutter logo~~ | 1.2 | ✅ Done 2026-08-13 |
| 3 | ~~No adaptive / monochrome icon~~ | 1.2 | ✅ Done — round icon N/A, see 1.2 |
| 4 | ~~Native splash is white~~ | 1.3 | ✅ Done 2026-08-13 |
| 5 | ~~No Android 12+ splash-screen config~~ | 1.3 | ✅ Done 2026-08-13 |
| 6 | ~~`android:label` is lowercase~~ | 2.3 | ✅ Done 2026-08-13 |
| 7 | Website not publicly hosted → no privacy URL, no `app-ads.txt` | 0.3 | ❌ Blocks listing |
| 8 | No Play Console account / 12-tester gate not started | 0.1, 6.2 | ❌ 14+ day lead time |
| 9 | ~~`min`/`targetSdk` not pinned~~ | 2.3 | ✅ Done — pinned 24 / 36 |
| 10 | No consent message published in AdMob (code is ready, config isn't) | 3.3 | ⚠️ Silent revenue loss |
| 11 | ~~No way to re-open the consent form from Settings~~ | 3.3 | ✅ Done 2026-08-13 |
| 12 | ~~OFL fonts bundled with no attribution surface~~ | 3.4 | ✅ Done — registered, surfaced, tested |
| 13 | ~~Audio licensing not documented~~ | 3.4 | ✅ Cleared — Adobe Firefly, commercial use granted |
| 14 | ~~Empty `music/` but a music toggle exists~~ | 1.4 | ✅ Row now hidden until loops ship |
| 15 | Only one block theme shipped vs. a theme system | 1.4 | ✅ Confirmed intentional — no picker exists |
| 16 | ~30 unused font files inflating the bundle | 5.2 | ⚠️ Size |
| 17 | ~~`allowBackup` undecided~~ | 2.3 | ✅ Decided — explicit `true` |
| 18 | No store graphics (icon 512, feature graphic, screenshots) | 4.6 | ❌ Blocks listing |
| 19 | ~~No listing copy written~~ | 4.3–4.5 | ✅ Short (73 ch) + full (1,668 ch) final in 4.4/4.5, verified against source |
| 20 | No screenshot capture mode — board states can't be staged | 4.7 | ⚠️ Blocks good screenshots |
| 21 | ~~Stale `// TODO:` comments in `build.gradle.kts`~~ | 2.2 | ✅ Both deleted |
| 22 | ~~"Tetrofall" trademark proximity unreviewed~~ | 3.5 | ✅ Reviewed — proceed, see `branding/store/trademark-review.md` |
| 23 | 2 pre-existing test failures (`widget_test`, `gesture_handler_test`) | 5.1 | ❌ Blocks the release build |
| 24 | Privacy-policy contact email may not be a real mailbox | 3.1 | ❌ Failed data-deletion route |

---

## Command reference

```bash
# Icons + splash (after adding the dev deps and branding/ artwork)
dart run flutter_launcher_icons
dart run flutter_native_splash:create

# Pre-flight
flutter clean && flutter pub get
flutter analyze && flutter test

# Release build
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols/<version>

# Verify the signature is yours, not the debug key.
# NOT `keytool -printcert -jarfile` — v1/JAR signing is off (minSdk 24), so
# keytool prints nothing and silence looks like success. See 2.2.
flutter build apk --release
$ANDROID_HOME/build-tools/36.0.0/apksigner verify -v --print-certs \
  build/app/outputs/flutter-apk/app-release.apk

# Install a release build on a connected device
flutter install --release

# Deobfuscate a crash from Play Console
flutter symbolize -i stack.txt \
  -d build/symbols/<version>/app.android-arm64.symbols
```

---

## Version history

Fill in as you ship. Every row is one upload to Play.

| versionCode | versionName | Track | Date | Git tag | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | 1.0.0 | — | — | — | Not yet uploaded |

---

## Critical-path timeline

The two long poles are Play account verification and the 14-day tester window.
Everything in Phases 1–5 can proceed in parallel with them.

```
Day 0    ├── Play account registration + verification  ──┐
         ├── Website deployment                          │  (parallel)
         └── Phase 1 icons/splash + Phase 2 signing ─────┤
Day 3-7  ├── Phase 3 compliance + Phase 4 store page ────┤
         └── Phase 5 QA on release build ────────────────┘
Day 7    ├── Internal testing upload, pre-launch report
Day 8    ├── Closed test opens ── 12 testers must opt in
Day 22   ├── 14-day window closes → apply for production access
Day 24+  ├── Production access granted
Day 25   └── Production release, 10% staged rollout
```

Realistic first-launch window: **3.5–5 weeks** from today, dominated by waiting,
not by work. Which is exactly why Phase 0 starts today.
