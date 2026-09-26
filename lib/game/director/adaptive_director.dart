import 'dart:math' as math;

import '../ai/placement_scorer.dart';
import '../engine/board_metrics.dart';
import '../engine/tetromino.dart';
import 'director.dart';

/// The Director that steers endless play, in two tiers:
///
///  * **rescue only** ([pacing] false): when the stack gets dangerously tall
///    the floor slows and the next rows are gifts under the player's well.
///  * **full** ([pacing] true): adds the build / peak / relief wave, skill
///    scaling, row styles, best-fit bag picks, breathers, lucky streaks and a
///    graceful ending.
///
/// Everything it does is bounded and smooth, and none of it changes anything
/// the player can already see.
class AdaptiveDirector implements Director {
  AdaptiveDirector({
    required this.skill,
    this.pacing = true,
    math.Random? random,
  }) : _random = random ?? math.Random();

  /// 0 (new) to 1 (expert). Fixed for the run; [SkillModel] moves it between
  /// runs.
  final double skill;

  final bool pacing;
  final math.Random _random;

  @override
  void Function(DirectorEvent event)? onEvent;

  DirectorStats _stats = DirectorStats();

  @override
  DirectorStats get stats => _stats;

  @override
  bool get isActive => true;

  static const _rescueEnter = 0.8;
  static const _rescueExit = 0.6;
  static const _rescueCooldown = 10.0;
  static const _rescueScale = 1.5;

  /// Rows from the top at which a run counts as a comeback.
  static const _comebackRows = 2;
  static const _maxComebacks = 2;

  static const _reliefScale = 1.3;
  static const _peakScale = 0.85;
  static const _breatherScale = 1.3;
  static const _breatherSeconds = 4.0;

  /// The wave's own deviation from baseline never exceeds this...
  static const _maxDeviation = 0.35;

  /// ...but a rescue is allowed to go past it, up to here.
  static const _hardMax = 1.75;

  static const _luckyEvery = 120.0;
  static const _lerpSeconds = 3.0;

  double _elapsed = 0;
  double _runStart = 0;
  double _lastClearAt = 0;
  double _stress = 0;
  BoardMetrics? _metrics;
  double _currentScale = 1.0;

  DirectorPhase _phase = DirectorPhase.build;
  double _phaseEnds = 0;
  bool _lucky = false;
  double _nextLuckyAt = _luckyEvery;

  bool _rescue = false;
  double _rescueCooldownUntil = 0;
  int _picksSinceBias = 2;
  double _breatherUntil = 0;

  /// Full help at the low end of skill, none above 0.8.
  double get _skillHelp => ((0.8 - skill) / 0.6).clamp(0.0, 1.0);

  double get _runSeconds => _elapsed - _runStart;

  /// The run length aimed for, by skill. Past it, help fades so runs still
  /// end.
  double get _targetRunSeconds => skill < 0.5
      ? 180 + (300 - 180) * (skill / 0.5)
      : 300 + 180 * (skill - 0.5) / 0.5;

  double get _fade {
    if (!pacing) return 1.0;
    return 1.0 - ((_runSeconds - _targetRunSeconds) / 60).clamp(0.0, 1.0);
  }

  double get _help => _skillHelp * _fade;

  @override
  void reset({required double elapsed}) {
    _stats = DirectorStats();
    _elapsed = elapsed;
    _runStart = elapsed;
    _lastClearAt = elapsed;
    _stress = 0;
    _metrics = null;
    _currentScale = 1.0;
    _phase = DirectorPhase.build;
    _phaseEnds = elapsed + _buildLength();
    _lucky = false;
    _nextLuckyAt = elapsed + _luckyEvery;
    _rescue = false;
    _rescueCooldownUntil = elapsed;
    _picksSinceBias = 2;
    _breatherUntil = 0;
  }

  @override
  DirectorOutput update(BoardSnapshot snapshot, double dt) {
    _elapsed = snapshot.elapsed;
    _metrics = snapshot.metrics;
    _stress = _computeStress(snapshot.metrics);

    _updateRescue(snapshot.metrics);
    if (pacing) _updatePhase();

    final target = _targetScale();
    // Ease toward the target; a lurch in rise speed would be felt.
    final step = _lerpSeconds <= 0 ? 1.0 : math.min(1.0, dt / _lerpSeconds);
    _currentScale += (target - _currentScale) * step;
    return DirectorOutput(riseIntervalScale: _currentScale);
  }

  double _computeStress(BoardMetrics m) {
    final cols = m.heights.length;
    final height = ((m.tallestFraction - 0.3) / 0.6).clamp(0.0, 1.0);
    final holes = (m.coveredHoles / (cols * 3)).clamp(0.0, 1.0);
    final sinceClear = ((_elapsed - _lastClearAt) / 30).clamp(0.0, 1.0);
    final bump = (m.bumpiness / (cols * 6)).clamp(0.0, 1.0);
    return 0.5 * height + 0.2 * holes + 0.2 * sinceClear + 0.1 * bump;
  }

  bool _nearTop(BoardMetrics m) => m.tallest >= m.rows - _comebackRows;

  void _updateRescue(BoardMetrics m) {
    if (!_rescue) {
      if (_elapsed < _rescueCooldownUntil || _help <= 0) return;
      final comeback = _nearTop(m) && _stats.comebacks < _maxComebacks;
      if (_stress > _rescueEnter || comeback) {
        _rescue = true;
        _stats.rescues++;
        if (comeback) _stats.comebacks++;
        onEvent?.call(RescueStarted(stress: _stress, comeback: comeback));
      }
      return;
    }
    if (_stress < _rescueExit && !_nearTop(m)) {
      _rescue = false;
      _rescueCooldownUntil = _elapsed + _rescueCooldown;
      _stats.rescuesSurvived++;
      onEvent?.call(RescueEnded(stress: _stress, survived: true));
    }
  }

  double _buildLength() => 35 + _random.nextDouble() * 10;
  double _peakLength() => 10 + _random.nextDouble() * 5;
  static const _reliefLength = 15.0;

  void _updatePhase() {
    // A rescue is its own relief.
    if (_rescue) return;

    if (_phase == DirectorPhase.build &&
        _lucky == false &&
        _skillHelp > 0.3 &&
        _runSeconds >= _nextLuckyAt) {
      _nextLuckyAt += _luckyEvery;
      _lucky = true;
      _enter(DirectorPhase.relief, _reliefLength);
      return;
    }

    if (_elapsed < _phaseEnds) return;
    switch (_phase) {
      case DirectorPhase.build:
        // Never send a struggling player into a peak.
        if (_stress > 0.6) {
          _enter(DirectorPhase.relief, _reliefLength);
        } else {
          _enter(DirectorPhase.peak, _peakLength());
        }
      case DirectorPhase.peak:
        _enter(DirectorPhase.relief, _reliefLength);
      case DirectorPhase.relief:
        _lucky = false;
        _enter(DirectorPhase.build, _buildLength());
    }
  }

  void _enter(DirectorPhase phase, double length) {
    _phase = phase;
    _phaseEnds = _elapsed + length;
    onEvent?.call(PhaseChanged(phase));
  }

  double _targetScale() {
    // Peaks sharpen with skill.
    final amplitude = 0.3 + 0.7 * skill;
    final phaseFactor = !pacing
        ? 1.0
        : switch (_phase) {
            DirectorPhase.build => 1.0,
            DirectorPhase.peak => 1 - (1 - _peakScale) * amplitude,
            DirectorPhase.relief => _reliefScale,
          };
    // Beginners get a slower floor; from skill ~0.7 up it is neutral.
    final skillFactor = pacing ? math.max(1.0, 1.25 - 0.35 * skill) : 1.0;
    final breather = pacing && _elapsed < _breatherUntil ? _breatherScale : 1.0;

    var wave = phaseFactor * skillFactor * breather;
    // Only the helpful half of the wave fades; a peak never does.
    if (wave > 1) wave = 1 + (wave - 1) * _fade;
    wave = wave.clamp(1 - _maxDeviation, 1 + _maxDeviation);

    final rescue = _rescue ? _rescueScale : 1.0;
    return (wave * rescue).clamp(1 - _maxDeviation, _hardMax);
  }

  @override
  void onPlacement(PlacementReport report) {
    final range = PlacementScorer.range(report.grid, report.type);
    if (!range.best.isFinite || range.best <= range.worst) return;
    final cells = Tetromino.cellsFor(report.type, report.rotation);
    final actual = PlacementScorer.score(
      report.grid,
      cells,
      report.anchorRow,
      report.anchorCol,
      blunder: false,
    );
    _stats.addPlacement(
      ((actual - range.worst) / (range.best - range.worst)).clamp(0.0, 1.0),
    );
  }

  @override
  void onClear({required int lines, required int chainIndex}) {
    _lastClearAt = _elapsed;
    if (!pacing) return;
    final big = lines >= 4 || chainIndex >= 2;
    if (!big) return;
    _breatherUntil = _elapsed + _breatherSeconds;
    // A big clear earns a breath, and for newer players a relief phase.
    if (!_rescue && _phase != DirectorPhase.relief && skill < 0.7) {
      _enter(DirectorPhase.relief, _reliefLength);
    }
  }

  @override
  bool takeBagBias() {
    _picksSinceBias++;
    final help = _help;
    if (help <= 0) return false;
    // At most one biased pick in three.
    if (_picksSinceBias < 3) return false;

    double chance;
    if (_rescue) {
      chance = 1.0;
    } else if (!pacing) {
      return false;
    } else {
      chance = switch (_phase) {
        DirectorPhase.relief => _lucky ? 1.0 : 0.5,
        DirectorPhase.build => skill < 0.4 ? 0.2 : 0.0,
        DirectorPhase.peak => 0.0,
      };
    }
    if (chance <= 0 || _random.nextDouble() >= chance) return false;
    _picksSinceBias = 0;
    _stats.bagBiasPicks++;
    return true;
  }

  @override
  RowPlan takeRowPlan() {
    final help = _help;
    final well = _metrics?.wellColumn;

    if (_rescue && help > 0) {
      _stats.giftRows++;
      return RowPlan(RowStyle.gift, wellColumn: well);
    }
    if (!pacing) return RowPlan.normal;

    switch (_phase) {
      case DirectorPhase.relief:
        final chance = _lucky ? 1.0 : 0.5 * help;
        if (help > 0 && _random.nextDouble() < chance) {
          _stats.giftRows++;
          return RowPlan(RowStyle.gift, wellColumn: well);
        }
        return RowPlan.normal;
      case DirectorPhase.peak:
        // Tough rows wait for the scattered regime (after the first minute),
        // where they only add the two-column spacing.
        return skill >= 0.5 && _elapsed >= 60
            ? const RowPlan(RowStyle.tough)
            : RowPlan.normal;
      case DirectorPhase.build:
        if (skill < 0.5 && _random.nextDouble() < help + 0.2) {
          return RowPlan(RowStyle.friendly, wellColumn: well);
        }
        return RowPlan.normal;
    }
  }

  @override
  void onRunEnded() {
    if (_rescue) {
      _rescue = false;
      onEvent?.call(RescueEnded(stress: _stress, survived: false));
    }
  }
}
