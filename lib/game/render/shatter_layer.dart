import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../config/motion.dart';
import '../engine/events.dart';

const _shardBaseColors = <Color>[
  Color(0xFFB97F4E),
  Color(0xFFA96F42),
  Color(0xFF8F5730),
  Color(0xFFC98F5C),
  Color(0xFF9C6238),
];
const _shardFacetColors = <Color>[
  Color(0xFFE8D3B0),
  Color(0xFFF2E7D2),
  Color(0xFFF7F1E4),
  Color(0xFFDDBE93),
];
const _shardEdgeColor = Color(0xFF6E4225);
const _crackColor = Color(0xFF4A2C16);

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
  Color baseColor = const Color(0x00000000);
  Color facetColor = const Color(0x00000000);

  final Float32List verts = Float32List(10);
  int vertexCount = 0;

  final Path path = Path();
  final Path facetPath = Path();

  void rebuildPaths() {
    path.reset();
    facetPath.reset();
    if (vertexCount < 3) return;
    path.moveTo(verts[0] * size, verts[1] * size);
    for (var i = 1; i < vertexCount; i++) {
      path.lineTo(verts[i * 2] * size, verts[i * 2 + 1] * size);
    }
    path.close();
    var cx = 0.0;
    var cy = 0.0;
    for (var i = 0; i < vertexCount; i++) {
      cx += verts[i * 2];
      cy += verts[i * 2 + 1];
    }
    cx /= vertexCount;
    cy /= vertexCount;
    facetPath.moveTo(verts[0] * size, verts[1] * size);
    facetPath.lineTo(verts[2] * size, verts[3] * size);
    facetPath.lineTo(cx * size, cy * size);
    facetPath.close();
  }
}

class _CrackedCell {
  _CrackedCell({
    required this.row,
    required this.col,
    required this.remaining,
    required this.seed,
  });

  final int row;
  final int col;
  double remaining;
  final int seed;
}

class ShatterLayer extends PositionComponent with HasGameReference {
  ShatterLayer({required this.theme});

  final ThemeDefinition theme;
  double cellSize = 1;

  final List<_Shard> _pool = List.generate(
    Motion.particlePoolSize,
    (_) => _Shard(),
  );
  int _cursor = 0;
  final _random = math.Random();

  final List<_CrackedCell> _crackedCells = [];

  ui.Image? _tile;

  static String _stripImagesPrefix(String path) {
    const prefix = 'assets/images/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  @override
  Future<void> onLoad() async {
    final path = theme.baseTileAsset;
    unawaited(
      game.images.load(_stripImagesPrefix(path)).then((img) => _tile = img),
    );
  }

  void addClear(List<ClearedCell> cells, int cols, {int linesCleared = 1}) {
    final center = (cols - 1) / 2.0;
    final stepSeconds = Motion.shatterStep.inMilliseconds / 1000;
    final crackSeconds = Motion.crackHold.inMilliseconds / 1000;

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
      final delay = crackSeconds + (cell.col - center).abs() * stepSeconds;
      _crackedCells.add(
        _CrackedCell(
          row: cell.row,
          col: cell.col,
          remaining: delay,
          seed: _random.nextInt(1 << 31),
        ),
      );
      final t = center == 0 ? 0.0 : (cell.col - center) / center;
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
      ..baseColor = _shardBaseColors[_random.nextInt(_shardBaseColors.length)]
      ..facetColor =
          _shardFacetColors[_random.nextInt(_shardFacetColors.length)];

    final vertexCount = 4 + _random.nextInt(2);
    shard.vertexCount = vertexCount;
    final angleStep = 2 * math.pi / vertexCount;
    for (var i = 0; i < vertexCount; i++) {
      final a = i * angleStep + (_random.nextDouble() - 0.5) * angleStep * 0.7;
      final r = 0.3 + _random.nextDouble() * 0.35;
      shard.verts[i * 2] = math.cos(a) * r;
      shard.verts[i * 2 + 1] = math.sin(a) * r;
    }
    shard.rebuildPaths();
  }

  void reset() {
    for (final shard in _pool) {
      shard.active = false;
    }
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

    final basePaint = Paint();
    final facetPaint = Paint();
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, cellSize * 0.03);
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

      canvas.save();
      canvas.translate(shard.x, shard.y);
      canvas.rotate(shard.angle);
      basePaint.color = shard.baseColor.withValues(alpha: opacity);
      facetPaint.color = shard.facetColor.withValues(alpha: opacity);
      edgePaint.color = _shardEdgeColor.withValues(alpha: opacity * 0.7);
      canvas.drawPath(shard.path, basePaint);
      canvas.drawPath(shard.facetPath, facetPaint);
      canvas.drawPath(shard.path, edgePaint);
      canvas.restore();
    }
  }

  void _renderCrackedCells(Canvas canvas) {
    if (_crackedCells.isEmpty) return;
    final tile = _tile;
    for (final cell in _crackedCells) {
      final rect = Rect.fromLTWH(
        cell.col * cellSize + cellSize * 0.015,
        cell.row * cellSize + cellSize * 0.015,
        cellSize * 0.97,
        cellSize * 0.97,
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(cellSize * 0.06),
      );
      if (tile == null) {
        canvas.drawRRect(rrect, Paint()..color = theme.blockTint);
      } else {
        canvas.save();
        canvas.clipRRect(rrect);
        final srcInset = tile.width * 0.03;
        canvas.drawImageRect(
          tile,
          Rect.fromLTWH(
            srcInset,
            srcInset,
            tile.width - srcInset * 2,
            tile.height - srcInset * 2,
          ),
          rect,
          Paint(),
        );
        canvas.restore();
      }

      final rng = math.Random(cell.seed);
      final crackPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, cellSize * 0.045)
        ..color = _crackColor.withValues(alpha: 0.75);
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
        canvas.drawPath(path, crackPaint);
      }
    }
  }
}
