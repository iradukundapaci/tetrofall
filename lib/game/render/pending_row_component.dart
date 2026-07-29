import 'package:flame/components.dart';

import '../../models/theme_definition.dart';
import '../config/board_config.dart';
import '../config/motion.dart';
import '../engine/cell.dart';
import 'block_component.dart';

/// The emerging row (§2.1), sitting one row below the visible floor in the
/// same content layer as everything else — [BoardComponent] applies a
/// single `-riseProgress * cellSize` offset to that whole layer, which is
/// all that's needed to make this component slide from fully hidden below
/// the floor to flush with it. A [ClipComponent] ancestor (in
/// [BoardComponent]) hides the part still below the floor.
class PendingRowComponent extends PositionComponent {
  PendingRowComponent({required this.theme});

  final ThemeDefinition theme;

  List<Cell?> row = List.filled(BoardConfig.cols, null);

  /// Mirrors `RiseController.riseProgress` — drives the fade-in.
  double riseProgress = 0.0;

  final List<BlockComponent> _blocks = [];

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < BoardConfig.cols; i++) {
      final b = BlockComponent(theme: theme);
      _blocks.add(b);
      await add(b);
    }
  }

  void updateLayout(double cellSize) {
    position = Vector2(0, BoardConfig.rows * cellSize);
    size = Vector2(BoardConfig.cols * cellSize, cellSize);
    for (var c = 0; c < BoardConfig.cols; c++) {
      _blocks[c].setLayout(cellSize: cellSize, row: 0, col: c);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Fade in 0.5 -> 1.0 across the first 30% of this row's travel.
    final fadeT = (riseProgress / Motion.riseEmergeFadeFraction).clamp(
      0.0,
      1.0,
    );
    final opacity = 0.5 + 0.5 * fadeT;
    for (var c = 0; c < BoardConfig.cols; c++) {
      final block = _blocks[c];
      block.blockVisible = row[c] != null;
      block.opacity = opacity;
    }
  }
}
