# Branding masters

Source artwork for the store and the launcher (android_release_plan.md §1.1).
Committed as source, **not** bundled into the app — nothing here is listed in
`pubspec.yaml`'s `assets:`. The build consumes these files once, at generation
time, through `flutter_launcher_icons` and `flutter_native_splash`.

## Don't hand-edit these PNGs

They are rendered from code by `tools/branding/forge_test.dart`, so the mark on
the launcher icon is geometrically the same T-tetromino `LogoMark` draws on the
splash and the main menu. Editing the PNGs makes the two drift.

```bash
flutter test tools/branding/forge_test.dart      # rewrites every file below
dart run flutter_launcher_icons                   # → android/.../mipmap-*
dart run flutter_native_splash:create             # → android/.../drawable*, values*
```

The drawing lives in `tools/branding/icon_art.dart`; change the art there.

## Files

| File | Size | What it is |
| --- | --- | --- |
| `icon_master.png` | 1024² | Full-bleed launcher icon: wood plate + gold T. No alpha, no rounded corners, no baked mask — Android applies its own. |
| `icon_foreground.png` | 1024² | Adaptive foreground. Gold T alone on transparent, inside the 683px (66%) safe circle. |
| `icon_background.png` | 1024² | Adaptive background. The wood plate alone. |
| `icon_monochrome.png` | 1024² | Android 13+ themed icon. Flat white silhouette on transparent — the system replaces the colour and keeps only the alpha. |
| `play_icon_512.png` | 512² | Play Store listing icon. Same art as the master, 32-bit PNG, 267 KB (limit 1 MB). |
| `splash_logo.png` | 1152² | Native splash mark for **Android 12+**, on transparent, 620px of art inside the inner 768px keyline. Deliberately the **wood** `LogoMark`, not the gold icon mark, so the native splash hands off to `SplashScreen`'s drop animation without the mark changing colour. |
| `splash_logo_legacy.png` | 1152² | Same mark for **pre-Android 12**, at 520px — see below. |
| `contact_sheet.png` | 1600×560 | Proof sheet — see below. |

## Why there are two splash images

The mark has to land at the same on-screen size on both splash paths, matching
the 130dp `SplashScreen` draws a frame later. The two paths scale a source image
completely differently:

- **Android 12+** maps the whole 1152px canvas onto a 240dp icon slot, so 620px
  of art → 129dp. It also clips to a 768px (160dp) keyline, which 620px clears.
- **Pre-12**, `flutter_native_splash` treats the source as xxxhdpi and divides
  it down per density, so the source is in *physical pixels at 4×*: 520px of
  art → 130dp on every device.

One image cannot satisfy both. `pubspec.yaml` wires `image:` to the legacy file
and `android_12.image:` to the other.

## Why the icon mark is gold but the splash mark is wood

`LogoMark` draws wood-toned blocks, which is right on the app's dark background
but sits too close to the wood plate behind it to survive a 48px launcher icon.
The icon mark keeps the identical geometry (cells, 12.5% gaps, 20% corners) and
the identical light direction, and changes only the fill to gold, plus a soft
halo. The splash mark has no such problem — it is `LogoMark` itself.

## contact_sheet.png

The two checks §1.1 asks for that a 1024px master cannot answer. Every masked
form of the icon — legacy squircle, adaptive under a circular mask (zoomed 1.5×,
exactly as Android crops the 108dp layers to a 72dp viewport), themed
monochrome, and the splash mark — at **192 / 96 / 48 px**, over a white and a
black wallpaper. Regenerate and eyeball it after any change to the art.

## Not yet produced (Phase 4)

`feature_graphic.png` (1024×500) and `store/shot_*.png` are Phase 4.6–4.10 and
land in `branding/store/`.
