import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/config/motion.dart';
import 'package:tetrofall/game/engine/cell.dart';
import 'package:tetrofall/game/engine/grid.dart';
import 'package:tetrofall/game/engine/piece_controller.dart';
import 'package:tetrofall/game/engine/tetromino.dart';

/// Lock-delay behaviour: a grounded piece stays under the player's control
/// for the full delay, and no longer than that.
void main() {
  const step = 1 / 60;
  final lockSteps = (Motion.lockDelay.inMilliseconds / 1000 * 60).ceil();

  /// An O piece resting on the floor, with gravity parked so the tests below
  /// exercise the lock delay and nothing else.
  PieceController groundedO(Grid grid) {
    final controller = PieceController(grid)
      ..dropInterval = const Duration(hours: 1)
      ..spawn(TetrominoType.O);
    controller.hardDrop();
    return controller;
  }

  /// Nudges the piece one column, alternating direction so every move is
  /// legal — a move refused by a wall never reaches the reset budget.
  bool shuffle(PieceController controller, int i) =>
      i.isEven ? controller.moveLeft() : controller.moveRight();

  test('a grounded piece still moves after the reset budget is spent', () {
    final controller = groundedO(Grid());

    // Shuffle along the floor the way a player does while lining up a
    // placement. Spending the budget used to lock the piece on the spot —
    // mid-shuffle, under the finger — instead of merely being the last
    // nudge that bought more time.
    for (var i = 0; i < Motion.lockResetLimit + 5; i++) {
      expect(
        controller.tick(step),
        PieceTickResult.continues,
        reason: 'nudge $i must not slam the piece down',
      );
      expect(
        shuffle(controller, i),
        isTrue,
        reason: 'nudge $i must still be accepted',
      );
    }

    expect(controller.piece, isNotNull);
  });

  test('the lock delay still expires once the reset budget is spent', () {
    final controller = groundedO(Grid());

    for (var i = 0; i <= Motion.lockResetLimit; i++) {
      controller.tick(step);
      shuffle(controller, i);
    }

    // Past the budget, moves no longer buy time, so the delay runs out and
    // the piece locks rather than hovering for as long as the player fidgets.
    var result = PieceTickResult.continues;
    for (
      var i = 0;
      i < lockSteps + 2 && result == PieceTickResult.continues;
      i++
    ) {
      result = controller.tick(step);
      shuffle(controller, i);
    }

    expect(result, PieceTickResult.locked);
  });

  test('stepping off a ledge and back cannot refresh the delay for free', () {
    final grid = Grid();
    // A two-wide pillar directly under the O's spawn columns, so the piece
    // lands on top of it and can be walked off its right edge and back.
    final spawnCol = Tetromino.spawnColumn[TetrominoType.O]!;
    grid.set(grid.maxRow, spawnCol, Cell(BlockType.wood));
    grid.set(grid.maxRow, spawnCol + 1, Cell(BlockType.wood));

    final controller = groundedO(grid);
    expect(
      controller.piece!.anchorRow,
      grid.maxRow - 2,
      reason: 'the piece should be resting on the pillar, not the floor',
    );

    // Re-grounding zeroed the lock timer outside the reset budget, so this
    // cycle — off the edge, then back onto the pillar — could be repeated
    // forever without the piece ever locking.
    var result = PieceTickResult.continues;
    for (var i = 0; i < 400 && result == PieceTickResult.continues; i++) {
      result = controller.tick(step);
      switch (i % 4) {
        case 0 || 1:
          controller.moveRight();
        default:
          controller.moveLeft();
      }
    }

    expect(result, PieceTickResult.locked);
  });
}
