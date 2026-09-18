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

/// One leg of a journey: a run of steps in a single direction, with its own
/// share of the flight time and its own curve.
class _Segment {
  _Segment(this.from, this.to, this.seconds, {required this.vertical});

  final (int row, int col) from;
  final (int row, int col) to;
  final double seconds;
  final bool vertical;
}

/// A block travelling a [BlockPath] — sideways, downward, or around a corner
/// (`boosters.md` §6.0). Consecutive steps in the same direction are merged
/// into one segment, so a five-cell slide is one motion and not five.
class _TravellingBlock {
  _TravellingBlock(this.segments, this.target);

  final List<_Segment> segments;
  final (int row, int col) target;

  int index = 0;
  double elapsed = 0;
  bool landed = false;
  double impactElapsed = 0;

  _Segment get current => segments[index];
  bool get endsFalling => segments.isNotEmpty && segments.last.vertical;
}

class FallAnimator extends PositionComponent {
  FallAnimator({required this.theme});

  final ThemeDefinition theme;
  double cellSize = 1;

  final List<_FallingBlock> _falls = [];
  final List<BlockComponent> _pool = [];

  final List<_TravellingBlock> _travels = [];
  final List<BlockComponent> _travelPool = [];

  // Packed as row * cols + col rather than a (row, col) record: the board
  // renderer probes this once per occupied cell per frame, and a record
  // literal per probe allocated tens of thousands of objects a second.
  final Set<int> _activeTargets = {};

  static int _targetKey(int row, int col) => row * BoardConfig.cols + col;

  bool isFallTarget(int row, int col) =>
      _activeTargets.contains(_targetKey(row, col));

  bool get isAnimating => _falls.isNotEmpty || _travels.isNotEmpty;

  void reset() {
    _activeTargets.clear();
    _falls.clear();
    _travels.clear();
    for (final block in [..._pool, ..._travelPool]) {
      block
        ..blockVisible = false
        ..removeFromParent();
    }
    _pool.clear();
    _travelPool.clear();
  }

  /// Blocks a booster carried somewhere. The grid already holds the result —
  /// logic commits instantly and the render layer animates toward it
  /// (`game.md` §2 golden rule) — so these draw over the destination cell
  /// until they arrive, exactly as a fall does.
  void addPaths(List<BlockPathEvent> paths) {
    for (final event in paths) {
      final cells = event.path.cells;
      if (cells.length < 2) continue;

      final segments = _segmentsFor(cells, event.durationSeconds);
      if (segments.isEmpty) continue;

      final target = cells.last;
      _travels.add(_TravellingBlock(segments, target));
      _activeTargets.add(_targetKey(target.$1, target.$2));
      if (_travelPool.length < _travels.length) {
        final b = BlockComponent(theme: theme);
        _travelPool.add(b);
        add(b);
      }
    }
  }

  /// Splits a path into same-direction runs and shares the flight time out
  /// between them by how long each would take on its own — so the sideways
  /// legs stay at a flat [Motion.boosterSlideStep] per cell and the drops
  /// stay on the gravity curve, however the engine scaled the total.
  List<_Segment> _segmentsFor(List<(int, int)> cells, double totalSeconds) {
    final runs = <((int, int), (int, int), bool)>[];
    var start = cells.first;
    var previous = cells.first;
    bool? vertical;

    for (var i = 1; i < cells.length; i++) {
      final cell = cells[i];
      final stepVertical = cell.$1 != previous.$1;
      if (vertical != null && stepVertical != vertical) {
        runs.add((start, previous, vertical));
        start = previous;
      }
      vertical = stepVertical;
      previous = cell;
    }
    if (vertical != null) runs.add((start, previous, vertical));

    // Weight each run by its natural cost, then rescale to the budget the
    // engine handed down.
    final weights = [
      for (final (from, to, isVertical) in runs)
        isVertical
            ? math.sqrt(2 * (to.$1 - from.$1).abs() / Motion.gravityCellsPerS2)
            : (to.$2 - from.$2).abs() *
                  Motion.boosterSlideStep.inMilliseconds /
                  1000,
    ];
    final sum = weights.fold(0.0, (a, b) => a + b);
    if (sum <= 0) return const [];

    return [
      for (var i = 0; i < runs.length; i++)
        _Segment(
          runs[i].$1,
          runs[i].$2,
          math.max(totalSeconds * weights[i] / sum, 1e-4),
          vertical: runs[i].$3,
        ),
    ];
  }

  void addFalls(List<BlockFallEvent> falls) {
    for (final f in falls) {
      final distance = (f.toRow - f.fromRow).abs();
      if (distance == 0) continue;
      _falls.add(
        _FallingBlock(
          col: f.col,
          fromRow: f.fromRow,
          toRow: f.toRow,
          // The engine paces the resolve, so it owns the flight time too.
          fallDuration: math.max(f.durationSeconds, 1e-6),
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

    _updateTravels(dt, impactSeconds);

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

  void _updateTravels(double dt, double impactSeconds) {
    for (var i = _travels.length - 1; i >= 0; i--) {
      final travel = _travels[i];
      final block = _travelPool[i];
      block
        ..blockVisible = true
        ..size = Vector2.all(cellSize);

      if (!travel.landed) {
        travel.elapsed += dt;
        var segment = travel.current;
        // A fast segment can be crossed inside one frame, and a tilt can
        // stack several of them, so carry the overflow forward rather than
        // spending a frame per leg.
        while (travel.elapsed >= segment.seconds &&
            travel.index < travel.segments.length - 1) {
          travel.elapsed -= segment.seconds;
          travel.index++;
          segment = travel.current;
        }

        final t = (travel.elapsed / segment.seconds).clamp(0.0, 1.0);
        // Falling legs accelerate; sideways legs are flat, so a slide reads
        // as travel rather than as a bounce (§6.0).
        final eased = segment.vertical
            ? Curves.easeInQuad.transform(t)
            : t.toDouble();
        final row = segment.from.$1 + (segment.to.$1 - segment.from.$1) * eased;
        final col = segment.from.$2 + (segment.to.$2 - segment.from.$2) * eased;
        block.position = Vector2(col * cellSize, row * cellSize);

        if (t >= 1.0) {
          travel.landed = true;
          // Dust only where the journey actually ended in a drop.
          if (travel.endsFalling) {
            add(
              DustPuff(
                at: Vector2(
                  (travel.target.$2 + 0.5) * cellSize,
                  (travel.target.$1 + 1) * cellSize,
                ),
                cellSize: cellSize,
                theme: theme,
              ),
            );
          }
        }
      } else {
        travel.impactElapsed += dt;
        final it = impactSeconds <= 0
            ? 1.0
            : (travel.impactElapsed / impactSeconds).clamp(0.0, 1.0);
        block
          ..position = Vector2(
            travel.target.$2 * cellSize,
            travel.target.$1 * cellSize,
          )
          // Squash is the landing tell, so a block that slid to a stop keeps
          // its shape.
          ..squashY = travel.endsFalling
              ? 1.0 - 0.15 * math.sin(math.pi * it)
              : 1.0;
        if (it >= 1.0) {
          _activeTargets.remove(_targetKey(travel.target.$1, travel.target.$2));
          block
            ..blockVisible = false
            ..squashY = 1.0;
          _travels.removeAt(i);
          _travelPool.removeAt(i)
            ..blockVisible = false
            ..removeFromParent();
        }
      }
    }
  }
}
