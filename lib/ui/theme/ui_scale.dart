import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Every size is authored against a 375x812 reference frame and rendered
/// through this, with two scalars:
///
///  * [s] — geometry: `min(w / 375, h / 812)`. Height-sensitive on purpose:
///    the board is 9:16, so every point of vertical chrome comes off its
///    width, and chrome must shrink when the screen is short.
///  * [t] — type, damped toward 1.0 so small text stays readable.
@immutable
class UiScale {
  const UiScale._(this.s, this.t, this.size, this.viewPadding);

  static const refWidth = 375.0;
  static const refHeight = 812.0;

  /// The floor keeps a 360x640 phone from driving captions under 10pt; the
  /// ceiling stops a tablet becoming a scaled-up phone.
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

  /// For one-off reference numbers that don't earn a token.
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

  double get radiusSm => Tokens.radiusSm * s;
  double get radiusMd => Tokens.radiusMd * s;
  double get radiusLg => Tokens.radiusLg * s;

  /// A sentinel, not a dimension: a pill is a pill at any size.
  static const radiusPill = Tokens.radiusPill;

  double get iconSm => Tokens.iconSm * s;
  double get iconMd => Tokens.iconMd * s;

  /// Never below 44: a smaller touch target is an accessibility regression.
  double get tap => math.max(44.0, Tokens.tapTarget * s);

  /// The HUD can never be shorter than the button it holds.
  double get hudHeight => math.max(tap, Tokens.hudHeight * s);

  double get borderThick => math.max(1.5, Tokens.borderThick * s);

  /// Shared modal width, capped to what the viewport leaves room for.
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

/// Installed in `TetrofallApp`'s `MaterialApp.builder`, above the Navigator.
class UiScaleScope extends InheritedWidget {
  const UiScaleScope({super.key, required this.scale, required super.child});

  final UiScale scale;

  /// The fallback keeps bare-`MaterialApp` tests and the capture harness
  /// laying out without a scope.
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
