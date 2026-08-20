import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Every size in the app is authored against screens.md's 375x812 device
/// frame and rendered through this.
///
/// Two scalars rather than one:
///
///  * [s] — geometry. Derived from the *fit* of the reference frame into the
///    real one, `min(w / 375, h / 812)`. Deliberately height-sensitive: the
///    board is 18x32 (= 9:16), so on a 9:16 phone every point of chrome the
///    layout spends vertically comes straight off the board's *width*. Chrome
///    has to shrink when the screen is short, not only when it is narrow.
///
///  * [t] — type, damped toward 1.0. Text scaled linearly with [s] goes
///    unreadable at the bottom of the range (12pt down to 9.6pt); damped it
///    lands at 10.6pt, while a 40pt display heading still gives back 5pt of
///    the height the board wants.
@immutable
class UiScale {
  const UiScale._(this.s, this.t, this.size, this.viewPadding);

  static const refWidth = 375.0;
  static const refHeight = 812.0;

  /// The floor keeps a 360x640 phone (raw fit 0.788) from driving 12pt
  /// captions under 10pt. The ceiling stops a tablet, where the fit is
  /// height-bound well above 1, from becoming a scaled-up phone.
  static const minScale = 0.80;
  static const maxScale = 1.25;
  static const _typeDamping = 0.6;

  /// Geometry scale: spacing, radii, icons, strokes, control sizes.
  final double s;

  /// Type scale: font sizes only.
  final double t;

  final Size size;
  final EdgeInsets viewPadding;

  factory UiScale.fromParts(Size size, EdgeInsets viewPadding) {
    final fit = math.min(size.width / refWidth, size.height / refHeight);
    final s = fit.clamp(minScale, maxScale);
    return UiScale._(s, 1 + (s - 1) * _typeDamping, size, viewPadding);
  }

  /// Escape hatches for one-off reference numbers that don't earn a token.
  double px(double reference) => reference * s;
  double font(double reference) => reference * t;

  double get fontXs => Tokens.fontSizeXs * t;
  double get fontSm => Tokens.fontSizeSm * t;
  double get fontMd => Tokens.fontSizeMd * t;
  double get fontLg => Tokens.fontSizeLg * t;
  double get fontXl => Tokens.fontSizeXl * t;
  double get fontXxl => Tokens.fontSizeXxl * t;
  double get fontHero => Tokens.fontSizeHero * t;

  double get spaceXs => Tokens.spaceXs * s;
  double get spaceSm => Tokens.spaceSm * s;
  double get spaceMd => Tokens.spaceMd * s;
  double get spaceLg => Tokens.spaceLg * s;
  double get spaceXl => Tokens.spaceXl * s;
  double get spaceXxl => Tokens.spaceXxl * s;

  double get radiusSm => Tokens.radiusSm * s;
  double get radiusMd => Tokens.radiusMd * s;
  double get radiusLg => Tokens.radiusLg * s;

  /// A pill is a pill at any size — this one is a sentinel, not a dimension.
  static const radiusPill = Tokens.radiusPill;

  double get iconSm => Tokens.iconSm * s;
  double get iconMd => Tokens.iconMd * s;
  double get iconLg => Tokens.iconLg * s;

  /// Never below 44: a scaled-down touch target is an accessibility
  /// regression, not a responsive one. This is also what retires the 44-vs-48
  /// split between settings' mute button and [CircleIconButton].
  double get tap => math.max(44.0, Tokens.tapTarget * s);

  /// The HUD can never be shorter than the button it holds.
  double get hudHeight => math.max(tap, Tokens.hudHeight * s);

  double get hairline => math.max(1.0, s);
  double get borderThick => math.max(1.5, Tokens.borderThick * s);

  /// Shared width for a centred modal: scaled, but never wider than the
  /// viewport leaves room for.
  double get panelWidth =>
      math.min(size.width - spaceLg * 2, Tokens.panelWidth * s);

  @override
  bool operator ==(Object other) =>
      other is UiScale &&
      other.size == size &&
      other.viewPadding == viewPadding;

  @override
  int get hashCode => Object.hash(size, viewPadding);
}

/// Installed once, in `TetrofallApp`'s `MaterialApp.builder`, above the
/// Navigator — so every pushed route sees it without doing anything.
class UiScaleScope extends InheritedWidget {
  const UiScaleScope({super.key, required this.scale, required super.child});

  final UiScale scale;

  /// The fallback is not a nicety. `tutorial_overlay_test.dart` and
  /// `gesture_hint_test.dart` pump a bare `MaterialApp`, and the capture
  /// harness under `tools/` mounts screens outside the app shell; both have
  /// to keep laying out without installing a scope of their own.
  static UiScale of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiScaleScope>()?.scale ??
      UiScale.fromParts(
        MediaQuery.sizeOf(context),
        MediaQuery.viewPaddingOf(context),
      );

  @override
  bool updateShouldNotify(UiScaleScope old) => old.scale != scale;
}

extension UiScaleContext on BuildContext {
  UiScale get scale => UiScaleScope.of(this);
}
