import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../boosters/booster_run_state.dart';
import '../boosters/booster_type.dart';
import '../config/board_config.dart';

/// The aim overlay: what the armed booster would take, outlined on the board
/// (`boosters.md` §4.4).
///
/// The board dims to 70% behind it and the ghost piece goes, so the outline is
/// the only bright thing on the board while a booster is armed. An invalid
/// target jitters — §9.3: invalid is a shake, never a color.
class BoosterPreviewLayer extends PositionComponent {
  BoosterPreviewLayer({required this.state, required this.theme});

  final BoosterRunState state;
  final ThemeDefinition theme;

  double cellSize = 1;

  int _lastShakeToken = 0;
  double _shakeRemaining = 0;

  static const _shakeDuration = 0.15;
  static const _shakeAmplitude = 3.0;

  late final Paint _scrim = Paint()
    ..color = Colors.black.withValues(alpha: 0.3);
  late final Paint _fill = Paint()..color = theme.accent.withValues(alpha: 0.2);
  late final Paint _stroke = Paint()
    ..color = theme.accent
    ..style = PaintingStyle.stroke;

  @override
  void update(double dt) {
    super.update(dt);
    if (state.shakeToken != _lastShakeToken) {
      _lastShakeToken = state.shakeToken;
      _shakeRemaining = _shakeDuration;
    }
    if (_shakeRemaining > 0) {
      _shakeRemaining = math.max(0, _shakeRemaining - dt);
    }
  }

  @override
  void render(Canvas canvas) {
    final type = state.armedType;
    if (type == null || cellSize <= 0) return;

    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        BoardConfig.cols * cellSize,
        BoardConfig.rows * cellSize,
      ),
      _scrim,
    );

    // Tilt and Earthquake depend on the whole settle, so there is nothing
    // per-cell to promise; the swipe arrows carry the instruction instead
    // (§5.11 Preview).
    if (type == BoosterType.tilt) {
      _drawTiltArrows(canvas);
      return;
    }

    final dx = _shakeRemaining <= 0
        ? 0.0
        : math.sin(_shakeRemaining / _shakeDuration * math.pi * 6) *
              _shakeAmplitude;

    _stroke.strokeWidth = math.max(1.5, cellSize * 0.08);
    for (final (row, col) in state.preview) {
      final rect = Rect.fromLTWH(
        col * cellSize + dx,
        row * cellSize,
        cellSize,
        cellSize,
      );
      canvas.drawRect(rect, _fill);
      canvas.drawRect(rect.deflate(_stroke.strokeWidth / 2), _stroke);
    }
  }

  /// The two directions Tilt can lean, drawn over the middle of the board.
  void _drawTiltArrows(Canvas canvas) {
    final width = BoardConfig.cols * cellSize;
    final height = BoardConfig.rows * cellSize;
    final y = height / 2;
    final reach = cellSize * 2.4;
    final paint = Paint()
      ..color = theme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, cellSize * 0.14)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final sign in [-1, 1]) {
      final tip = width / 2 + sign * (width / 2 - cellSize * 0.8);
      final tail = tip - sign * reach;
      canvas.drawLine(Offset(tail, y), Offset(tip, y), paint);
      canvas.drawLine(
        Offset(tip, y),
        Offset(tip - sign * cellSize * 0.8, y - cellSize * 0.8),
        paint,
      );
      canvas.drawLine(
        Offset(tip, y),
        Offset(tip - sign * cellSize * 0.8, y + cellSize * 0.8),
        paint,
      );
    }
  }
}
