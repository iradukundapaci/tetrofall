import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';

import '../../models/theme_definition.dart';
import '../../ui/theme/tokens.dart';

class BoardFrame extends PositionComponent {
  BoardFrame({
    required this.cols,
    required this.rows,
    required double cellSize,
    this.theme = ThemeDefinition.classicWood,
  }) : _cellSize = cellSize,
       super(size: Vector2(cols * cellSize, rows * cellSize));

  final int cols;
  final int rows;
  final ThemeDefinition theme;

  double _cellSize;
  double get cellSize => _cellSize;
  set cellSize(double value) {
    _cellSize = value;
    size = Vector2(cols * value, rows * value);
  }

  bool warning = false;
  double _warnClock = 0;

  ui.Image? _woodTexture;

  // The theme tint below uses BlendMode.color, a non-separable blend the
  // raster backend resolves through an offscreen pass. Applying it to a
  // board-sized image every frame was a fixed, permanent tax; bake it once
  // per board size instead. Capped in resolution because this is a soft
  // out-of-focus wood photo — nobody can see the difference, and it keeps
  // the cached texture small.
  static const _maxBakedPx = 1024;
  ui.Image? _bakedBackground;
  Size? _bakedFor;

  @override
  Future<void> onLoad() async {
    _woodTexture = await Flame.images.load('textures/bg_wood.png');
  }

  @override
  void onRemove() {
    _bakedBackground?.dispose();
    _bakedBackground = null;
    _bakedFor = null;
    super.onRemove();
  }

  ui.Image? _background() {
    final texture = _woodTexture;
    if (texture == null || size.x <= 0 || size.y <= 0) return null;

    final target = Size(size.x, size.y);
    if (_bakedFor == target) return _bakedBackground;

    final dpr =
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    final longest = math.max(size.x, size.y) * dpr;
    final scale = longest > _maxBakedPx ? _maxBakedPx / longest : dpr;
    final width = math.max(1, (size.x * scale).round());
    final height = math.max(1, (size.y * scale).round());

    final imgW = texture.width.toDouble();
    final imgH = texture.height.toDouble();
    final cover = math.max(size.x / imgW, size.y / imgH);
    final srcW = size.x / cover;
    final srcH = size.y / cover;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      texture,
      Rect.fromLTWH((imgW - srcW) / 2, (imgH - srcH) / 2, srcW, srcH),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        // Colorize (hue + saturation from the theme, luminance from the
        // photo) rather than swap the asset per theme — classic_wood's
        // frameLight is already this same warm tan, so this is a no-op for
        // the shipping look, but it means a new theme only needs a palette
        // entry, never a new frame texture.
        ..colorFilter = ColorFilter.mode(theme.frameLight, BlendMode.color),
    );
    final picture = recorder.endRecording();

    _bakedBackground?.dispose();
    _bakedBackground = picture.toImageSync(width, height);
    picture.dispose();
    _bakedFor = target;
    return _bakedBackground;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _warnClock = warning ? _warnClock + dt : 0;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    final background = _background();
    if (background == null) {
      canvas.drawRect(rect, Paint()..color = theme.boardBg);
    } else {
      canvas.drawImageRect(
        background,
        Rect.fromLTWH(
          0,
          0,
          background.width.toDouble(),
          background.height.toDouble(),
        ),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // Grooves stay live rather than baked: seventeen lines a frame is
    // nothing, and baking them into a downscaled texture would soften them.
    final groovePaint = Paint()
      ..color = theme.frameDark.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, cellSize * 0.035);
    for (var c = 1; c < cols; c++) {
      final x = c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), groovePaint);
    }

    if (warning) {
      final pulse = (math.sin(2 * math.pi * _warnClock) + 1) / 2;
      final alpha = 0.12 + 0.22 * pulse;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, cellSize * 2),
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            Offset(rect.center.dx, cellSize * 2),
            [
              Tokens.colorRed.withValues(alpha: alpha),
              Tokens.colorRed.withValues(alpha: 0),
            ],
          ),
      );
    }
  }
}
