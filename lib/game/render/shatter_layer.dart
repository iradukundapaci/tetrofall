import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../config/motion.dart';
import '../engine/events.dart';
import 'shard_palette.dart';

/// One pooled shard slot. Reused via a ring-buffer cursor rather than
/// allocated per-particle (game.md §2.3: a 4-line clear is ~500 particles,
/// and per-frame allocation would GC-hitch). `active` marks a slot that's
/// currently a live shard; inactive slots simply aren't drawn or updated.
class _Shard {
  bool active = false;
  double delay = 0;
  double elapsed = 0;
  double lifetime = 0;
  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;
  double size = 0;
  double angle = 0;
  double rotationSpeed = 0;
  Color color = const Color(0x00000000);
}

/// The signature center-out shatter animation (§2.3). Cells destined to
/// clear are handed to [addClear] the instant the engine emits
/// [RowsClearedEvent] — each cell schedules its own delay
/// (`(col - center).abs() * shatterStep`) so the burst visibly propagates
/// outward from the row's middle, then fires 10-14 wooden-shard particles.
/// Purely decorative: particles never block game logic and outlive
/// `RESOLVING` entirely, which is why this component's lifetime tracking
/// is fully independent of [GameEngine]'s resolve timer.
class ShatterLayer extends PositionComponent {
  ShatterLayer({required this.theme});

  final ThemeDefinition theme;
  double cellSize = 1;

  final List<_Shard> _pool = List.generate(
    Motion.particlePoolSize,
    (_) => _Shard(),
  );
  int _cursor = 0;
  final _random = math.Random();

  /// Schedules a burst for every cell in [cells] (already removed from the
  /// logical grid by the time this is called — §3.1's golden rule: logic
  /// commits instantly, render catches up). [cols] is the board width,
  /// needed to find the row's center column for the delay formula.
  void addClear(List<ClearedCell> cells, int cols) {
    final center = (cols - 1) / 2.0;
    final stepSeconds = Motion.shatterStep.inMilliseconds / 1000;
    for (final cell in cells) {
      final delay = (cell.col - center).abs() * stepSeconds;
      final color = ShardPalette.colorFor(cell.type, theme);
      final count =
          Motion.particlesPerCellMin +
          _random.nextInt(
            Motion.particlesPerCellMax - Motion.particlesPerCellMin + 1,
          );
      for (var i = 0; i < count; i++) {
        _spawn(row: cell.row, col: cell.col, delay: delay, color: color);
      }
    }
  }

  void _spawn({
    required int row,
    required int col,
    required double delay,
    required Color color,
  }) {
    final shard = _pool[_cursor];
    _cursor = (_cursor + 1) % _pool.length;

    final lifetimeMs = _lerpInt(
      Motion.shardMinLifetime.inMilliseconds,
      Motion.shardMaxLifetime.inMilliseconds,
      _random.nextDouble(),
    );
    final spin = _random.nextBool() ? 1.0 : -1.0;

    shard
      ..active = true
      ..delay = delay
      ..elapsed = 0
      ..lifetime = lifetimeMs / 1000
      ..x = (col + 0.5) * cellSize
      ..y = (row + 0.5) * cellSize
      ..vx = _lerpD(Motion.shardMinVx, Motion.shardMaxVx, _random.nextDouble())
      ..vy = _lerpD(Motion.shardMinVy, Motion.shardMaxVy, _random.nextDouble())
      ..size = _lerpD(
        Motion.shardMinSize,
        Motion.shardMaxSize,
        _random.nextDouble(),
      )
      ..angle = _random.nextDouble() * 2 * math.pi
      ..rotationSpeed =
          spin *
          _lerpD(
            Motion.shardMinRotationSpeed,
            Motion.shardMaxRotationSpeed,
            _random.nextDouble(),
          )
      ..color = color;
  }

  /// Deactivates every pooled shard immediately, for a restart (§4) — a
  /// clear mid-shatter shouldn't leave shards from the ended run animating
  /// over the fresh board.
  void reset() {
    for (final shard in _pool) {
      shard.active = false;
    }
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;
  static int _lerpInt(int a, int b, double t) => (a + (b - a) * t).round();

  @override
  void update(double dt) {
    super.update(dt);
    for (final shard in _pool) {
      if (!shard.active) continue;
      if (shard.delay > 0) {
        shard.delay -= dt;
        continue;
      }
      shard.elapsed += dt;
      if (shard.elapsed >= shard.lifetime) {
        shard.active = false;
        continue;
      }
      shard.vy += Motion.particleGravity * dt;
      shard.x += shard.vx * dt;
      shard.y += shard.vy * dt;
      shard.angle += shard.rotationSpeed * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint();
    for (final shard in _pool) {
      if (!shard.active || shard.delay > 0) continue;
      final t = shard.elapsed / shard.lifetime;
      final opacity = t <= Motion.shardFadeStartFraction
          ? 1.0
          : (1 - (t - Motion.shardFadeStartFraction) /
                    (1 - Motion.shardFadeStartFraction))
                .clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      canvas.save();
      canvas.translate(shard.x, shard.y);
      canvas.rotate(shard.angle);
      paint.color = shard.color.withValues(alpha: opacity);
      final half = shard.size / 2;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          Rect.fromLTWH(-half, -half, shard.size, shard.size),
          Radius.circular(half * 0.4),
        ),
        paint,
      );
      canvas.restore();
    }
  }
}
