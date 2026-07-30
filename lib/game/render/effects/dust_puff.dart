import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';

class DustPuff extends PositionComponent {
  DustPuff({required Vector2 at, required double cellSize})
    : _cellSize = cellSize,
      super(position: at, size: Vector2.zero());

  final double _cellSize;
  final _random = Random();
  static const _lifetime = 0.35;
  double _elapsed = 0;

  late final List<_Speck> _specks = List.generate(6, (_) {
    final angle = _random.nextDouble() * pi - pi;
    final speed = (0.4 + _random.nextDouble() * 0.6) * _cellSize;
    return _Speck(
      vx: cos(angle) * speed,
      vy: -sin(angle).abs() * speed * 0.6,
      radius: _cellSize * (0.05 + _random.nextDouble() * 0.05),
    );
  });

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _lifetime) {
      removeFromParent();
      return;
    }
    for (final s in _specks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += _cellSize * 3 * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _lifetime).clamp(0.0, 1.0);
    final opacity = (1 - t) * 0.6;
    if (opacity <= 0) return;
    final paint = Paint()..color = Tokens.colorText.withValues(alpha: opacity);
    for (final s in _specks) {
      canvas.drawCircle(Offset(s.x, s.y), s.radius, paint);
    }
  }
}

class _Speck {
  _Speck({required this.vx, required this.vy, required this.radius})
    : x = 0,
      y = 0;
  double x;
  double y;
  double vx;
  double vy;
  final double radius;
}
