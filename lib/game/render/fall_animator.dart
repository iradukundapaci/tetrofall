import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../models/theme_definition.dart';
import '../config/board_config.dart';
import '../config/motion.dart';
import '../engine/events.dart';
import 'block_component.dart';
import 'effects/dust_puff.dart';

class _FallingBlock {
  _FallingBlock({
    required this.col,
    required this.fromRow,
    required this.toRow,
    required this.fallDuration,
  });

  final int col;
  final int fromRow;
  final int toRow;
  final double fallDuration;

  double elapsed = 0;
  bool landed = false;
  double impactElapsed = 0;
}

class FallAnimator extends PositionComponent {
  FallAnimator({required this.theme});

  final ThemeDefinition theme;
  double cellSize = 1;

  final List<_FallingBlock> _falls = [];
  final List<BlockComponent> _pool = [];

  // Packed as row * cols + col rather than a (row, col) record: the board
  // renderer probes this once per occupied cell per frame, and a record
  // literal per probe allocated tens of thousands of objects a second.
  final Set<int> _activeTargets = {};

  static int _targetKey(int row, int col) => row * BoardConfig.cols + col;

  bool isFallTarget(int row, int col) =>
      _activeTargets.contains(_targetKey(row, col));

  bool get isAnimating => _falls.isNotEmpty;

  void reset() {
    _activeTargets.clear();
    _falls.clear();
    for (final block in _pool) {
      block
        ..blockVisible = false
        ..removeFromParent();
    }
    _pool.clear();
  }

  void addFalls(List<BlockFallEvent> falls) {
    for (final f in falls) {
      final distance = (f.toRow - f.fromRow).abs();
      if (distance == 0) continue;
      final duration = math.sqrt(2 * distance / Motion.gravityCellsPerS2);
      _falls.add(
        _FallingBlock(
          col: f.col,
          fromRow: f.fromRow,
          toRow: f.toRow,
          fallDuration: duration,
        ),
      );
      _activeTargets.add(_targetKey(f.toRow, f.col));
      if (_pool.length < _falls.length) {
        final b = BlockComponent(theme: theme);
        _pool.add(b);
        add(b);
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final impactSeconds = Motion.impactSquash.inMilliseconds / 1000;

    for (var i = _falls.length - 1; i >= 0; i--) {
      final f = _falls[i];
      final block = _pool[i];
      block
        ..blockVisible = true
        ..size = Vector2.all(cellSize);

      if (!f.landed) {
        f.elapsed += dt;
        final t = (f.elapsed / f.fallDuration).clamp(0.0, 1.0);
        final eased = Curves.easeInQuad.transform(t);
        final row = f.fromRow + (f.toRow - f.fromRow) * eased;
        block.position = Vector2(f.col * cellSize, row * cellSize);
        if (t >= 1.0) {
          f.landed = true;
          add(
            DustPuff(
              at: Vector2((f.col + 0.5) * cellSize, (f.toRow + 1) * cellSize),
              cellSize: cellSize,
              theme: theme,
            ),
          );
        }
      } else {
        f.impactElapsed += dt;
        final it = impactSeconds <= 0
            ? 1.0
            : (f.impactElapsed / impactSeconds).clamp(0.0, 1.0);
        block
          ..position = Vector2(f.col * cellSize, f.toRow * cellSize)
          ..squashY = 1.0 - 0.15 * math.sin(math.pi * it);
        if (it >= 1.0) {
          _activeTargets.remove(_targetKey(f.toRow, f.col));
          block.blockVisible = false;
          block.squashY = 1.0;
          _falls.removeAt(i);
          _pool.removeAt(i)
            ..blockVisible = false
            ..removeFromParent();
        }
      }
    }
  }
}
