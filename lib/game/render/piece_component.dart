import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../models/theme_definition.dart';
import '../config/motion.dart';
import '../engine/cell.dart';
import '../engine/game_engine.dart';
import '../tetrofall_game.dart';
import 'block_component.dart';

/// The active piece plus its ghost outline. Horizontal moves ease over
/// [Motion.horizontalMoveEase] — §2 requires no block ever teleport.
/// Vertical position snaps directly to the logical row: only horizontal
/// motion is smoothed (§2 doesn't ask for eased gravity, and snapping
/// vertically keeps the drop feeling crisp).
class PieceComponent extends PositionComponent with HasGameReference<TetrofallGame> {
  PieceComponent({required this.engine, required this.theme});

  final GameEngine engine;
  final ThemeDefinition theme;

  double cellSize = 1;

  final List<BlockComponent> _blocks = [];
  final List<BlockComponent> _ghostBlocks = [];

  double _visualCol = 0;
  double _easeFrom = 0;
  double _easeTarget = 0;
  double _easeT = 1;
  int? _lastCol;

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < 4; i++) {
      final block = BlockComponent(theme: theme);
      _blocks.add(block);
      await add(block);
      final ghostBlock = BlockComponent(theme: theme, ghost: true);
      _ghostBlocks.add(ghostBlock);
      await add(ghostBlock);
    }
  }

  @override
  void update(double dt) {
    final piece = engine.pieceController.piece;
    if (piece == null) {
      for (final b in _blocks) {
        b.blockVisible = false;
      }
      for (final b in _ghostBlocks) {
        b.blockVisible = false;
      }
      return;
    }

    if (_lastCol != piece.anchorCol) {
      _easeFrom = _lastCol == null ? piece.anchorCol.toDouble() : _visualCol;
      _easeTarget = piece.anchorCol.toDouble();
      _easeT = 0;
      _lastCol = piece.anchorCol;
    }

    final easeSeconds = Motion.horizontalMoveEase.inMilliseconds / 1000;
    if (_easeT < 1) {
      _easeT = (_easeT + (easeSeconds == 0 ? 1 : dt / easeSeconds)).clamp(
        0.0,
        1.0,
      );
      _visualCol =
          _easeFrom + (_easeTarget - _easeFrom) * Curves.easeOut.transform(_easeT);
    } else {
      _visualCol = _easeTarget;
    }

    final cells = piece.cells;
    for (var i = 0; i < 4; i++) {
      final offset = cells[i];
      final localRow = piece.anchorRow + offset.row;
      final visualCol = _visualCol + offset.col;
      _blocks[i]
        ..blockVisible = true
        ..blockType = BlockType.wood
        ..size = Vector2.all(cellSize)
        ..position = Vector2(visualCol * cellSize, localRow * cellSize);
    }

    final showGhost = game.showGhost;
    final ghostRow = engine.pieceController.ghostLandingRow();
    final ghostVisible =
        showGhost && ghostRow != null && ghostRow != piece.anchorRow;
    for (var i = 0; i < 4; i++) {
      final g = _ghostBlocks[i];
      g.blockVisible = ghostVisible;
      if (ghostVisible) {
        final offset = cells[i];
        g
          ..size = Vector2.all(cellSize)
          ..position = Vector2(
            (piece.anchorCol + offset.col) * cellSize,
            (ghostRow + offset.row) * cellSize,
          );
      }
    }
  }
}
