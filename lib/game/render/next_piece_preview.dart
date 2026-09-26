import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/theme/ui_scale.dart';
import '../engine/events.dart';
import '../engine/game_engine.dart';
import '../engine/tetromino.dart';

/// The piece after the one in play, drawn in the HUD.
///
/// It is the engine's lookahead slot, so what it shows is committed: the
/// Director may bias which piece is drawn *into* the slot, but never changes
/// one the player can already see.
class NextPiecePreview extends StatefulWidget {
  const NextPiecePreview({super.key, required this.engine});

  final GameEngine engine;

  @override
  State<NextPiecePreview> createState() => _NextPiecePreviewState();
}

class _NextPiecePreviewState extends State<NextPiecePreview> {
  @override
  void initState() {
    super.initState();
    widget.engine.addEventListener(_onEvent);
  }

  @override
  void dispose() {
    widget.engine.removeEventListener(_onEvent);
    super.dispose();
  }

  // The lookahead only changes when a piece spawns.
  void _onEvent(GameEvent event) {
    if (event is PieceSpawnedEvent && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final next = widget.engine.nextPiece;
    return Container(
      width: ui.tap * 1.3,
      height: ui.tap,
      decoration: BoxDecoration(
        color: Tokens.colorPanel,
        borderRadius: BorderRadius.circular(ui.radiusSm),
        border: Border.all(color: Tokens.colorPanelBorder),
      ),
      padding: EdgeInsets.all(ui.px(6)),
      child: next == null
          ? null
          : CustomPaint(painter: _PiecePainter(next), size: Size.infinite),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter(this.type);

  final TetrominoType type;

  @override
  void paint(Canvas canvas, Size size) {
    final cells = Tetromino.cellsFor(type, RotationState.spawn);
    final minRow = cells.map((c) => c.row).reduce(math.min);
    final maxRow = cells.map((c) => c.row).reduce(math.max);
    final minCol = cells.map((c) => c.col).reduce(math.min);
    final maxCol = cells.map((c) => c.col).reduce(math.max);
    final rows = maxRow - minRow + 1;
    final cols = maxCol - minCol + 1;

    final cell = math.min(size.width / cols, size.height / rows);
    final dx = (size.width - cell * cols) / 2;
    final dy = (size.height - cell * rows) / 2;

    final fill = Paint()..color = Tokens.colorWoodLight;
    final edge = Paint()
      ..color = Tokens.colorWoodDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, cell * 0.08);
    final radius = Radius.circular(cell * 0.18);

    for (final c in cells) {
      final rect = Rect.fromLTWH(
        dx + (c.col - minCol) * cell,
        dy + (c.row - minRow) * cell,
        cell,
        cell,
      ).deflate(cell * 0.04);
      final rrect = RRect.fromRectAndRadius(rect, radius);
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, edge);
    }
  }

  @override
  bool shouldRepaint(_PiecePainter old) => old.type != type;
}
