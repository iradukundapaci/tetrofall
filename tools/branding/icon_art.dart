/// The drawing side of the branding forge (android_release_plan.md §1.1).
///
/// Every master file is rendered from this one file so the launcher icon, the
/// Play listing icon and the native splash mark can never drift apart, and so
/// the T-tetromino geometry stays identical to `LogoMark` — the mark the app
/// itself draws on the splash and the main menu.
///
/// Run `tools/branding/forge_test.dart` to write the PNGs.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tetrofall/ui/theme/tokens.dart';

/// The T-tetromino laid out exactly as `LogoMark` lays it out: gaps at 12.5%
/// of a cell, corners at 20%, one cell on top of a three-cell crossbar.
class MarkGeometry {
  const MarkGeometry(this.cell);

  /// Sizes the mark by its overall width rather than by cell, because every
  /// safe zone in the spec is expressed as a fraction of the canvas.
  factory MarkGeometry.forWidth(double width) =>
      MarkGeometry(width / _widthInCells);

  static const _widthInCells = 3.25; // 3 cells + 2 gaps of 0.125.
  static const _heightInCells = 2.125; // 2 cells + 1 gap.

  final double cell;

  double get gap => cell * 0.125;
  double get radius => cell * 0.2;
  double get width => cell * _widthInCells;
  double get height => cell * _heightInCells;

  /// Top-left of each cell, relative to the mark's own bounding box.
  List<Offset> get cellOrigins {
    final step = cell + gap;
    return [
      Offset(step, 0), // stem
      Offset(0, step), // crossbar
      Offset(step, step),
      Offset(step * 2, step),
    ];
  }

  List<RRect> cellsAt(Offset markTopLeft) => [
    for (final origin in cellOrigins)
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          markTopLeft.dx + origin.dx,
          markTopLeft.dy + origin.dy,
          cell,
          cell,
        ),
        Radius.circular(radius),
      ),
  ];
}

/// How a mark's cells are filled.
enum MarkStyle {
  /// Gold-lit blocks for the launcher icon — the in-app wood tones sit too
  /// close to the wood plate behind them to read at 48px.
  gold,

  /// A flat single-colour silhouette for Android 13+ themed icons. The system
  /// tints this, so only the alpha channel survives.
  monochrome,
}

/// Draws the mark centred in the canvas at [markWidthFraction] of its width.
class MarkArt extends StatelessWidget {
  const MarkArt({
    super.key,
    required this.style,
    required this.markWidthFraction,
  });

  final MarkStyle style;
  final double markWidthFraction;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MarkPainter(style: style, markWidthFraction: markWidthFraction),
      size: Size.infinite,
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.style, required this.markWidthFraction});

  final MarkStyle style;
  final double markWidthFraction;

  static const _goldLight = Color(0xFFFFE39A);
  static const _goldEdge = Color(0xFFC1830F);

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = MarkGeometry.forWidth(size.width * markWidthFraction);
    final topLeft = Offset(
      (size.width - geometry.width) / 2,
      (size.height - geometry.height) / 2,
    );
    final cells = geometry.cellsAt(topLeft);

    if (style == MarkStyle.monochrome) {
      final paint = Paint()..color = Colors.white;
      for (final cell in cells) {
        canvas.drawRRect(cell, paint);
      }
      return;
    }

    final bounds = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      geometry.width,
      geometry.height,
    );

    // A warm halo so the mark separates from the plate even on a launcher
    // that dims the background layer.
    canvas.drawCircle(
      bounds.center,
      geometry.width * 0.72,
      Paint()
        ..shader = ui.Gradient.radial(
          bounds.center,
          geometry.width * 0.72,
          [
            Tokens.colorGold.withValues(alpha: 0.22),
            Tokens.colorGold.withValues(alpha: 0),
          ],
          [0.0, 1.0],
        ),
    );

    // Shadows go down first for every cell, so a cell never casts onto the
    // face of the neighbour it is touching.
    final shadow = Paint()
      ..color = const Color(0x73000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, geometry.cell * 0.1);
    for (final cell in cells) {
      canvas.drawRRect(cell.shift(Offset(0, geometry.cell * 0.06)), shadow);
    }

    // Same light direction as `_LogoBlock`: a diagonal from upper-left.
    for (final cell in cells) {
      canvas.drawRRect(
        cell,
        Paint()
          ..shader = ui.Gradient.linear(
            Alignment(-0.6, -1).withinRect(cell.outerRect),
            Alignment(0.6, 1).withinRect(cell.outerRect),
            const [_goldLight, Tokens.colorGold, _goldEdge],
            const [0.0, 0.55, 1.0],
          ),
      );
      // The bevel `_LogoBlock` fakes with an overlay gradient, because
      // Flutter has no inset shadow.
      canvas.drawRRect(
        cell,
        Paint()
          ..shader = ui.Gradient.linear(
            cell.outerRect.topCenter,
            cell.outerRect.bottomCenter,
            [
              Colors.white.withValues(alpha: 0.34),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.3),
            ],
            const [0.0, 0.25, 0.7, 1.0],
          ),
      );
      canvas.drawRRect(
        cell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = geometry.cell * 0.035
          ..color = const Color(0x8C2B1C12),
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.markWidthFraction != markWidthFraction;
}

/// The wood plate every icon sits on: the token gradient, the shipped board
/// texture as grain, and a vignette so the corners don't fight the mark.
class WoodPlate extends StatelessWidget {
  const WoodPlate({super.key, required this.texture});

  /// The decoded `assets/images/textures/bg_wood.png`, or null to fall back to
  /// a flat gradient.
  final ui.Image? texture;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PlatePainter(texture), size: Size.infinite);
  }
}

class _PlatePainter extends CustomPainter {
  const _PlatePainter(this.texture);

  final ui.Image? texture;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, const [
          Tokens.colorWoodMid,
          Tokens.colorWoodDark,
        ]),
    );

    final texture = this.texture;
    if (texture != null) {
      // Cover-fit the square texture into the square canvas.
      canvas.drawImageRect(
        texture,
        Rect.fromLTWH(
          0,
          0,
          texture.width.toDouble(),
          texture.height.toDouble(),
        ),
        rect,
        Paint()
          ..blendMode = BlendMode.overlay
          ..color = const Color(0x59000000), // 35% grain
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.width * 0.72,
          [Colors.transparent, Colors.black.withValues(alpha: 0.38)],
          const [0.45, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) =>
      oldDelegate.texture != texture;
}
