import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';
import '../config/motion.dart';
import '../engine/combo_tier.dart';

/// The blocks-destroyed combo banner (§1.7): "GOOD!" through
/// "UNBELIEVABLE!", purple accent, scale-pop + fade, in the reserved space
/// above the board. Renders in board-local coordinates but outside the
/// rise-scrolled content layer — the banner must stay fixed while the
/// stack drifts up behind it.
class ComboBanner extends PositionComponent {
  String? _text;
  double _elapsed = 0;

  static double get _totalSeconds =>
      (Motion.comboBannerPopIn + Motion.comboBannerHold + Motion.comboBannerFadeOut)
          .inMilliseconds /
      1000;

  void trigger(ComboTier tier) {
    _text = tier.label;
    _elapsed = 0;
  }

  /// Hides an in-progress banner immediately, for a restart (§4).
  void reset() {
    _text = null;
    _elapsed = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_text == null) return;
    _elapsed += dt;
    if (_elapsed >= _totalSeconds) _text = null;
  }

  @override
  void render(Canvas canvas) {
    final text = _text;
    if (text == null) return;

    final popInSeconds = Motion.comboBannerPopIn.inMilliseconds / 1000;
    final holdEnd = popInSeconds + Motion.comboBannerHold.inMilliseconds / 1000;

    double scale;
    double opacity;
    if (_elapsed < popInSeconds) {
      final t = (_elapsed / popInSeconds).clamp(0.0, 1.0);
      // Overshoot pop: 0.6 -> 1.15 -> settles by the time hold begins.
      scale = ui.lerpDouble(0.6, 1.15, Curves.easeOut.transform(t))!;
      opacity = t;
    } else if (_elapsed < holdEnd) {
      final t = ((_elapsed - popInSeconds) / (holdEnd - popInSeconds)).clamp(
        0.0,
        1.0,
      );
      scale = ui.lerpDouble(1.15, 1.0, Curves.easeOut.transform(t))!;
      opacity = 1.0;
    } else {
      final fadeSeconds = Motion.comboBannerFadeOut.inMilliseconds / 1000;
      final t = ((_elapsed - holdEnd) / fadeSeconds).clamp(0.0, 1.0);
      scale = 1.0;
      opacity = 1.0 - t;
    }
    if (opacity <= 0) return;

    final fontSize = size.x * 0.11;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Tokens.colorPurple.withValues(alpha: opacity),
          fontFamily: Tokens.fontDisplay,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: fontSize * 0.03,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.35 * opacity),
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }
}
