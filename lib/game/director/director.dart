import '../engine/board_metrics.dart';
import '../engine/grid.dart';
import '../engine/row_plan.dart';
import '../engine/tetromino.dart';

export '../engine/row_plan.dart';

/// Where a run is in the Director's build / peak / relief wave.
enum DirectorPhase { build, peak, relief }

/// The piece the player just placed, reported *before* it is written into the
/// grid, so the Director can compare it with the best placement that was
/// available on the board as it stood.
class PlacementReport {
  const PlacementReport({
    required this.grid,
    required this.type,
    required this.rotation,
    required this.anchorRow,
    required this.anchorCol,
  });

  final Grid grid;
  final TetrominoType type;
  final RotationState rotation;
  final int anchorRow;
  final int anchorCol;
}

/// What the Director sees of the board on each update.
class BoardSnapshot {
  const BoardSnapshot({required this.metrics, required this.elapsed});

  final BoardMetrics metrics;

  /// Seconds into the run's difficulty clock.
  final double elapsed;
}

class DirectorOutput {
  const DirectorOutput({this.riseIntervalScale = 1.0});

  static const neutral = DirectorOutput();

  /// Multiplies the rise interval: above 1 the floor rises more slowly.
  final double riseIntervalScale;
}

/// Things worth telling analytics about, raised as they happen.
sealed class DirectorEvent {
  const DirectorEvent();
}

class RescueStarted extends DirectorEvent {
  const RescueStarted({required this.stress, required this.comeback});
  final double stress;
  final bool comeback;
}

class RescueEnded extends DirectorEvent {
  const RescueEnded({required this.stress, required this.survived});
  final double stress;
  final bool survived;
}

class PhaseChanged extends DirectorEvent {
  const PhaseChanged(this.phase);
  final DirectorPhase phase;
}

/// Per-run counters, for the game-over summary and analytics.
class DirectorStats {
  int rescues = 0;
  int rescuesSurvived = 0;
  int comebacks = 0;
  int giftRows = 0;
  int bagBiasPicks = 0;
  int placements = 0;
  double _qualitySum = 0;

  /// Mean placement quality this run, 0 (worst available) to 1 (best), or null
  /// when nothing was measured.
  double? get placementQuality =>
      placements == 0 ? null : _qualitySum / placements;

  void addPlacement(double quality) {
    placements++;
    _qualitySum += quality;
  }
}

/// Watches the player and quietly steers the three levers the engine already
/// has: how fast the floor rises, what the next rows look like, and which
/// piece comes next.
///
/// It must feel like luck, never like cheating. So it never touches what the
/// player can already see — the visible pending row and the next-piece
/// preview — and every change is smooth and bounded.
abstract class Director {
  /// False for [NullDirector]: lets the engine skip the work of describing the
  /// board to something that will ignore it.
  bool get isActive;

  DirectorStats get stats;

  /// Raised as rescues start and end and as the pacing phase turns over.
  void Function(DirectorEvent event)? onEvent;

  /// Called when a run starts. [elapsed] is where the difficulty clock begins.
  void reset({required double elapsed});

  /// Called roughly four times a second while playing, and on every lock.
  /// [dt] is the time since the previous call.
  DirectorOutput update(BoardSnapshot snapshot, double dt);

  void onPlacement(PlacementReport report);

  void onClear({required int lines, required int chainIndex});

  /// Called once per piece drawn into the lookahead. True means: deal the
  /// remaining bag piece that best fits the board, instead of a random one.
  bool takeBagBias();

  /// Called when the floor rises, for the row that will appear after the one
  /// already showing.
  RowPlan takeRowPlan();

  /// Called when the run ends, so a rescue in progress can be closed out.
  void onRunEnded();
}

/// Always neutral. Used when the flag is off, and in any mode where every
/// player must get the identical game.
class NullDirector implements Director {
  NullDirector();

  @override
  bool get isActive => false;

  @override
  final DirectorStats stats = DirectorStats();

  @override
  void Function(DirectorEvent event)? onEvent;

  @override
  void reset({required double elapsed}) {}

  @override
  DirectorOutput update(BoardSnapshot snapshot, double dt) =>
      DirectorOutput.neutral;

  @override
  void onPlacement(PlacementReport report) {}

  @override
  void onClear({required int lines, required int chainIndex}) {}

  @override
  bool takeBagBias() => false;

  @override
  RowPlan takeRowPlan() => RowPlan.normal;

  @override
  void onRunEnded() {}
}
