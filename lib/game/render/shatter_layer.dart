import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../config/motion.dart';
import '../engine/events.dart';
import 'tile_cache.dart';

// Shard colors are derived from the active theme's block tint (below),
// not hardcoded — so a theme swap recolors the shatter effect along
// with the blocks, with zero changes needed here.
const _facetLightnessDeltas = [0.32, 0.38, 0.42, 0.26];

// Shards are drawn from a small pre-baked greyscale atlas that is tinted
// per shard, instead of three `drawPath` calls each. These are the greys the
// atlas bakes: the flat body, the lit facet, and the outline. Tinting by the
// shard's facet color reproduces the old base/facet/edge relationship,
// because every shard color was already a lightness variant of one hue.
const _spriteBodyGrey = 0.55;
const _spriteFacetGrey = 1.0;
const _spriteEdgeGrey = 0.30;

/// Shard silhouettes baked into the atlas. Each shard picks one at random;
/// with random rotation at 3-10dp on screen the repeat is invisible.
const _spriteCount = 12;
const _spritePx = 48;

/// Unit-space half-extent a sprite slot covers. Shard vertices reach 0.65
/// from center, so 0.7 leaves room for the outline stroke.
const _spriteExtent = 0.7;

Color _shiftLightness(Color color, double delta) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
}

List<Color> _tonalVariants(Color base, List<double> deltas) => [
  for (final d in deltas) _shiftLightness(base, d),
];

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
  int sprite = 0;
  Color tint = const Color(0x00000000);
}

class _CrackedCell {
  _CrackedCell({
    required this.row,
    required this.col,
    required this.remaining,
    required int seed,
    required double cellSize,
  }) : cellRect = Rect.fromLTWH(
         col * cellSize,
         row * cellSize,
         cellSize,
         cellSize,
       ),
       rect = Rect.fromLTWH(
         col * cellSize + cellSize * 0.015,
         row * cellSize + cellSize * 0.015,
         cellSize * 0.97,
         cellSize * 0.97,
       ) {
    // Built once. This geometry is fully determined by the seed, but it used
    // to be regenerated — new Random, new Paths, every segment — on every
    // frame the cell was on screen.
    final rng = math.Random(seed);
    final cx = rect.left + rect.width * (0.35 + rng.nextDouble() * 0.3);
    final cy = rect.top + rect.height * (0.35 + rng.nextDouble() * 0.3);
    final crackCount = 3 + rng.nextInt(3);
    for (var i = 0; i < crackCount; i++) {
      final path = Path()..moveTo(cx, cy);
      var a = rng.nextDouble() * 2 * math.pi;
      var px = cx;
      var py = cy;
      final segments = 2 + rng.nextInt(3);
      for (var s = 0; s < segments; s++) {
        final len = cellSize * (0.15 + rng.nextDouble() * 0.25);
        a += (rng.nextDouble() - 0.5) * 1.2;
        px = (px + math.cos(a) * len).clamp(rect.left, rect.right);
        py = (py + math.sin(a) * len).clamp(rect.top, rect.bottom);
        path.lineTo(px, py);
      }
      cracks.add(path);
    }
  }

  final int row;
  final int col;

  /// Full cell — the baked tile already carries the inset and rounding.
  final Rect cellRect;

  /// Inset content box the cracks are drawn inside.
  final Rect rect;

  final List<Path> cracks = [];
  double remaining;
}

/// The order a booster's cells come apart in — see [ShatterLayer.addBoosterBurst].
enum BurstSpread { rings, sweep, together }

class ShatterLayer extends PositionComponent {
  ShatterLayer({required this.theme})
    : _facetColors = _tonalVariants(theme.blockTint, _facetLightnessDeltas),
      _crackColor = _shiftLightness(theme.blockTint, -0.40);

  final ThemeDefinition theme;
  final List<Color> _facetColors;
  final Color _crackColor;
  double cellSize = 1;

  final List<_Shard> _pool = List.generate(
    Motion.particlePoolSize,
    (_) => _Shard(),
  );
  int _cursor = 0;
  int _activeCount = 0;
  final _random = math.Random();

  final List<_CrackedCell> _crackedCells = [];

  ui.Image? _shardAtlas;

  // Preallocated so a frame with 800 live shards allocates nothing.
  final Float32List _transforms = Float32List(Motion.particlePoolSize * 4);
  final Float32List _rects = Float32List(Motion.particlePoolSize * 4);
  final Int32List _colors = Int32List(Motion.particlePoolSize);

  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _crackPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _tilePaint = Paint()..filterQuality = FilterQuality.low;

  @override
  Future<void> onLoad() async {
    _shardAtlas = _bakeShardAtlas();
  }

  @override
  void onRemove() {
    _shardAtlas?.dispose();
    _shardAtlas = null;
    super.onRemove();
  }

  /// One image holding [_spriteCount] greyscale shard silhouettes side by
  /// side, each with its body, lit facet and outline already composited.
  ui.Image _bakeShardAtlas() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rng = math.Random(0xF00D);
    const half = _spritePx / 2.0;
    final bodyPaint = Paint()
      ..color = Color.from(
        alpha: 1,
        red: _spriteBodyGrey,
        green: _spriteBodyGrey,
        blue: _spriteBodyGrey,
      );
    final facetPaint = Paint()
      ..color = Color.from(
        alpha: 1,
        red: _spriteFacetGrey,
        green: _spriteFacetGrey,
        blue: _spriteFacetGrey,
      );
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _spritePx * 0.045
      ..color = Color.from(
        alpha: 0.7,
        red: _spriteEdgeGrey,
        green: _spriteEdgeGrey,
        blue: _spriteEdgeGrey,
      );

    for (var s = 0; s < _spriteCount; s++) {
      final originX = s * _spritePx.toDouble();
      final vertexCount = 4 + rng.nextInt(2);
      final xs = List<double>.filled(vertexCount, 0);
      final ys = List<double>.filled(vertexCount, 0);
      final angleStep = 2 * math.pi / vertexCount;
      for (var i = 0; i < vertexCount; i++) {
        final a = i * angleStep + (rng.nextDouble() - 0.5) * angleStep * 0.7;
        final r = 0.3 + rng.nextDouble() * 0.35;
        // Unit space [-extent, extent] maps onto the sprite's slot.
        xs[i] = originX + half + math.cos(a) * r / _spriteExtent * half;
        ys[i] = half + math.sin(a) * r / _spriteExtent * half;
      }

      final body = Path()..moveTo(xs[0], ys[0]);
      for (var i = 1; i < vertexCount; i++) {
        body.lineTo(xs[i], ys[i]);
      }
      body.close();

      var cx = 0.0;
      var cy = 0.0;
      for (var i = 0; i < vertexCount; i++) {
        cx += xs[i];
        cy += ys[i];
      }
      cx /= vertexCount;
      cy /= vertexCount;
      final facet = Path()
        ..moveTo(xs[0], ys[0])
        ..lineTo(xs[1], ys[1])
        ..lineTo(cx, cy)
        ..close();

      canvas.drawPath(body, bodyPaint);
      canvas.drawPath(facet, facetPaint);
      canvas.drawPath(body, edgePaint);
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(_spriteCount * _spritePx, _spritePx);
    picture.dispose();
    return image;
  }

  void addClear(
    List<ClearedCell> cells,
    int cols, {
    int linesCleared = 1,
    double timeScale = 1.0,
  }) {
    final center = (cols - 1) / 2.0;
    // The engine compresses the shatter as the game speeds up and as a chain
    // deepens; the crack sequence has to run on the same clock or it would
    // still be spreading when gravity takes over.
    final stepSeconds = Motion.shatterStep.inMilliseconds / 1000 * timeScale;
    final crackSeconds = Motion.crackHold.inMilliseconds / 1000 * timeScale;

    _addShatter(
      cells,
      linesCleared: linesCleared,
      delayFor: (cell) =>
          crackSeconds + (cell.col - center).abs() * stepSeconds,
      offCenterFor: (cell) => center == 0 ? 0.0 : (cell.col - center) / center,
    );
  }

  /// A booster's own shatter (`boosters.md` §6.1). Same shards, same pool,
  /// different order: a bomb breaks in rings out from the middle, a drill
  /// breaks in the direction the bit travels, and everything else falls back
  /// to the centre-out sequence a line clear uses.
  void addBoosterBurst(
    List<ClearedCell> cells,
    int cols, {
    (int row, int col)? origin,
    BurstSpread spread = BurstSpread.rings,
    double stepSeconds = 0.04,
    double leadSeconds = 0.0,
    double timeScale = 1.0,
  }) {
    if (cells.isEmpty) return;
    final step = stepSeconds * timeScale;
    final lead = leadSeconds * timeScale;
    final center = (cols - 1) / 2.0;
    final from = origin ?? (cells.first.row, cells.first.col);

    double delayFor(ClearedCell cell) => switch (spread) {
      BurstSpread.rings =>
        lead +
            step *
                math.max(
                  (cell.row - from.$1).abs(),
                  (cell.col - from.$2).abs(),
                ),
      BurstSpread.sweep => lead + step * (cell.col - from.$2).abs(),
      BurstSpread.together => lead,
    };

    _addShatter(
      cells,
      linesCleared: 1,
      delayFor: delayFor,
      // Shards are thrown away from where the booster hit rather than away
      // from the middle of the board, so a corner blast reads as a corner
      // blast.
      offCenterFor: (cell) =>
          center == 0 ? 0.0 : ((cell.col - from.$2) / center).clamp(-1.0, 1.0),
    );
  }

  void _addShatter(
    List<ClearedCell> cells, {
    required int linesCleared,
    required double Function(ClearedCell cell) delayFor,
    required double Function(ClearedCell cell) offCenterFor,
  }) {
    final lineBonus =
        (linesCleared - 1).clamp(0, 20) * Motion.particlesLineBonusPerExtraLine;
    final perCellMax = math.min(
      Motion.particlesPerCellMax + lineBonus,
      Motion.particlesPerCellCap,
    );
    final perCellMin = math.min(Motion.particlesPerCellMin, perCellMax);

    final estimatedTotal = cells.length * (perCellMin + perCellMax) / 2;
    final budgetScale = estimatedTotal > Motion.maxParticlesPerClear
        ? Motion.maxParticlesPerClear / estimatedTotal
        : 1.0;

    for (final cell in cells) {
      final delay = delayFor(cell);
      _crackedCells.add(
        _CrackedCell(
          row: cell.row,
          col: cell.col,
          remaining: delay,
          seed: _random.nextInt(1 << 31),
          cellSize: cellSize,
        ),
      );
      final t = offCenterFor(cell);
      final rawCount =
          perCellMin + _random.nextInt(perCellMax - perCellMin + 1);
      final count = math.max(1, (rawCount * budgetScale).round());
      for (var i = 0; i < count; i++) {
        _spawn(row: cell.row, col: cell.col, delay: delay, offCenter: t);
      }
    }
  }

  void _spawn({
    required int row,
    required int col,
    required double delay,
    required double offCenter,
  }) {
    final shard = _pool[_cursor];
    _cursor = (_cursor + 1) % _pool.length;
    // The pool is a ring, so this slot may still have been in flight.
    if (!shard.active) _activeCount++;

    final lifetimeMs = _lerpInt(
      Motion.shardMinLifetime.inMilliseconds,
      Motion.shardMaxLifetime.inMilliseconds,
      _random.nextDouble(),
    );
    final spin = _random.nextBool() ? 1.0 : -1.0;

    final up =
        _lerpD(
          Motion.shardMinUpSpeedCells,
          Motion.shardMaxUpSpeedCells,
          _random.nextDouble(),
        ) *
        (1.0 + 0.2 * offCenter.abs());
    final outward =
        offCenter * Motion.shardMaxOutwardSpeedCells +
        (_random.nextDouble() * 2 - 1) * Motion.shardOutwardJitterCells;

    shard
      ..active = true
      ..delay = delay
      ..elapsed = 0
      ..lifetime = lifetimeMs / 1000
      ..x = (col + 0.5) * cellSize
      ..y = (row + 0.5) * cellSize
      ..vx = outward * cellSize
      ..vy = -up * cellSize
      ..size =
          _lerpD(
            Motion.shardMinSizeCells,
            Motion.shardMaxSizeCells,
            _random.nextDouble(),
          ) *
          cellSize
      ..angle = _random.nextDouble() * 2 * math.pi
      ..rotationSpeed =
          spin *
          _lerpD(
            Motion.shardMinRotationSpeed,
            Motion.shardMaxRotationSpeed,
            _random.nextDouble(),
          )
      ..sprite = _random.nextInt(_spriteCount)
      ..tint = _facetColors[_random.nextInt(_facetColors.length)];
  }

  void reset() {
    for (final shard in _pool) {
      shard.active = false;
    }
    _activeCount = 0;
    _crackedCells.clear();
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;
  static int _lerpInt(int a, int b, double t) => (a + (b - a) * t).round();

  @override
  void update(double dt) {
    super.update(dt);
    for (var i = _crackedCells.length - 1; i >= 0; i--) {
      final cell = _crackedCells[i];
      cell.remaining -= dt;
      if (cell.remaining <= 0) {
        _crackedCells.removeAt(i);
      }
    }

    if (_activeCount == 0) return;
    final gravity = Motion.shardGravityCellsPerS2 * cellSize;
    for (final shard in _pool) {
      if (!shard.active) continue;
      if (shard.delay > 0) {
        shard.delay -= dt;
        continue;
      }
      shard.elapsed += dt;
      if (shard.elapsed >= shard.lifetime) {
        shard.active = false;
        _activeCount--;
        continue;
      }
      shard.vy += gravity * dt;
      shard.vx *= math.max(0, 1 - Motion.shardHorizontalDragPerS * dt);
      shard.x += shard.vx * dt;
      shard.y += shard.vy * dt;
      shard.angle += shard.rotationSpeed * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    _renderCrackedCells(canvas);

    final atlas = _shardAtlas;
    if (atlas == null || _activeCount == 0) return;

    // Every live shard goes out in one call. This was three `drawPath` per
    // shard, so a full-board four-line clear was issuing ~2400 path draws a
    // frame for the length of the effect.
    var count = 0;
    for (final shard in _pool) {
      if (!shard.active || shard.delay > 0) continue;
      final t = shard.elapsed / shard.lifetime;
      final opacity = t <= Motion.shardFadeStartFraction
          ? 1.0
          : (1 -
                    (t - Motion.shardFadeStartFraction) /
                        (1 - Motion.shardFadeStartFraction))
                .clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      // The sprite's slot spans 2 * extent in unit space, and a shard of
      // `size` reaches `extent * size` from its center.
      final scale = shard.size * _spriteExtent * 2 / _spritePx;
      final scos = math.cos(shard.angle) * scale;
      final ssin = math.sin(shard.angle) * scale;
      const anchor = _spritePx / 2.0;

      final i = count * 4;
      _transforms[i] = scos;
      _transforms[i + 1] = ssin;
      _transforms[i + 2] = shard.x - scos * anchor + ssin * anchor;
      _transforms[i + 3] = shard.y - ssin * anchor - scos * anchor;
      _rects[i] = shard.sprite * _spritePx.toDouble();
      _rects[i + 1] = 0;
      _rects[i + 2] = (shard.sprite + 1) * _spritePx.toDouble();
      _rects[i + 3] = _spritePx.toDouble();
      _colors[count] = shard.tint.withValues(alpha: opacity).toARGB32();
      count++;
    }
    if (count == 0) return;

    final used = count * 4;
    canvas.drawRawAtlas(
      atlas,
      Float32List.view(_transforms.buffer, 0, used),
      Float32List.view(_rects.buffer, 0, used),
      Int32List.view(_colors.buffer, 0, count),
      BlendMode.modulate,
      null,
      _atlasPaint,
    );
  }

  void _renderCrackedCells(Canvas canvas) {
    if (_crackedCells.isEmpty) return;
    final tile = TileCache.tile(theme, cellSize);
    _crackPaint
      ..strokeWidth = math.max(0.7, cellSize * 0.045)
      ..color = _crackColor.withValues(alpha: 0.75);

    for (final cell in _crackedCells) {
      if (tile == null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell.rect, Radius.circular(cellSize * 0.06)),
          Paint()..color = theme.blockTint,
        );
      } else {
        canvas.drawImageRect(
          tile,
          Rect.fromLTWH(0, 0, tile.width.toDouble(), tile.height.toDouble()),
          cell.cellRect,
          _tilePaint,
        );
      }
      for (final crack in cell.cracks) {
        canvas.drawPath(crack, _crackPaint);
      }
    }
  }
}
