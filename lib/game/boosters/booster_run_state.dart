import 'package:flutter/foundation.dart';

import '../config/booster_tuning.dart';
import '../engine/game_engine.dart';
import '../engine/events.dart';
import 'booster_target.dart';
import 'booster_type.dart';
import 'loadout.dart';

/// How one slot in the bar reads right now (`boosters.md` §4.2).
enum BoosterSlotState {
  /// Charge left, phase is `playing`, and there is something to hit.
  ready,

  /// An instant booster that would do nothing at this moment. The charge
  /// badge stays bright: the charge is still there.
  noTarget,

  /// Tapped, and waiting for the player to aim.
  armed,

  /// A resolve is running. Nothing in the bar is tappable.
  busy,

  /// Charge used, and a rewarded refill is still available (§4.9).
  spent,

  /// Charge used and no refill left this run.
  exhausted,
}

/// The booster half of a run: what was rolled, what is left of it, and what
/// the player is currently pointing at.
///
/// Owned by [TetrofallGame] and ticked from its update loop, so the aim
/// window counts down on the game's clock rather than on a widget's — a
/// paused game stops aiming, for free.
class BoosterRunState extends ChangeNotifier {
  BoosterRunState({required this.engine});

  final GameEngine engine;

  Loadout? _loadout;
  Loadout? get loadout => _loadout;

  /// Charges left per slot, indexed the same way [Loadout] is.
  final List<int> _charges = List.filled(4, 0);

  /// Rewarded refills spent on each slot, against
  /// [BoosterTuning.adRefillsPerBooster].
  final List<int> _refills = List.filled(4, 0);

  int _refillsThisRun = 0;
  int get refillsThisRun => _refillsThisRun;

  bool get canRefillAnything =>
      BoosterTuning.adRefillEnabled &&
      _refillsThisRun < BoosterTuning.adRefillsPerRun;

  /// Whether a rewarded video is actually available. §4.9 rule 4: never draw
  /// an offer that cannot be delivered — a slot with no ad behind it goes
  /// straight to exhausted rather than showing a button that does nothing.
  bool refillAvailable = false;

  int? _armedIndex;
  int? get armedIndex => _armedIndex;
  bool get isAiming => _armedIndex != null;
  BoosterType? get armedType =>
      _armedIndex == null ? null : _loadout?[_armedIndex!];

  /// Seconds left of the 4s aim window (§4.4). Drives the ring on the slot.
  double _aimRemaining = 0;
  double get aimProgress =>
      _armedIndex == null ? 0 : (_aimRemaining / _aimSeconds).clamp(0.0, 1.0);

  static double get _aimSeconds =>
      BoosterTuning.aimWindow.inMilliseconds / 1000;

  /// Where the finger is, while aiming, and what would go.
  BoosterTarget? _aim;
  BoosterTarget? get aim => _aim;
  List<(int, int)> _preview = const [];
  List<(int, int)> get preview => _preview;
  bool _previewValid = false;
  bool get previewValid => _previewValid;

  /// Counts up on an invalid release, so the preview can jitter for 150ms
  /// rather than turn red — §9.3: invalid is a shake, never a color.
  int _shakeToken = 0;
  int get shakeToken => _shakeToken;

  /// The one-line tip shown above the bar the first time a booster is used,
  /// and the boosters already tipped this session (§4.8).
  String? _tip;
  String? get tip => _tip;
  double _tipRemaining = 0;
  final Set<BoosterType> _tipped = {};

  void beginRun(Loadout loadout) {
    _loadout = loadout;
    for (var i = 0; i < _charges.length; i++) {
      _charges[i] = BoosterTuning.chargesPerBooster;
      _refills[i] = 0;
    }
    _refillsThisRun = 0;
    _clearAim();
    _tip = null;
    _tipRemaining = 0;
    notifyListeners();
  }

  /// Restart or quit: the charges and the refill counter both go. The loadout
  /// itself survives, because "Same boosters" is offered on the next roll
  /// (§4.7).
  void endRun() {
    _clearAim();
    notifyListeners();
  }

  int chargesAt(int index) => _charges[index];

  bool canRefillAt(int index) =>
      canRefillAnything &&
      refillAvailable &&
      _refills[index] < BoosterTuning.adRefillsPerBooster;

  BoosterSlotState stateAt(int index) {
    final loadout = _loadout;
    if (loadout == null) return BoosterSlotState.exhausted;
    if (_armedIndex == index) return BoosterSlotState.armed;
    if (_charges[index] <= 0) {
      return canRefillAt(index)
          ? BoosterSlotState.spent
          : BoosterSlotState.exhausted;
    }
    if (engine.phase != GamePhase.playing) return BoosterSlotState.busy;

    final type = loadout[index];
    // Only instant boosters can be "no target": an aimed one has no target
    // until the player picks one (§4.2).
    if (type.isInstant && !engine.canUseBooster(type, _instantTarget(type))) {
      return BoosterSlotState.noTarget;
    }
    return BoosterSlotState.ready;
  }

  /// Instant boosters fire on nothing; Tilt is instant to arm but needs the
  /// swipe direction before it can be judged, so it is probed without one.
  BoosterTarget _instantTarget(BoosterType type) =>
      const BoosterTarget.instant();

  // --- arming -------------------------------------------------------------

  /// A tap on a slot. Fires straight away if the booster needs no aim,
  /// otherwise arms it and starts the window (§4.3).
  ///
  /// Returns false when nothing happened, which is what the refill offer
  /// hangs off: a spent slot's tap *is* the offer, and the caller opens the
  /// sheet instead.
  bool tapSlot(int index) {
    final loadout = _loadout;
    if (loadout == null) return false;
    final state = stateAt(index);
    switch (state) {
      case BoosterSlotState.busy:
      case BoosterSlotState.spent:
      case BoosterSlotState.exhausted:
        return false;
      case BoosterSlotState.armed:
        cancelAim(BoosterCancelReason.tap);
        return true;
      case BoosterSlotState.noTarget:
        return false;
      case BoosterSlotState.ready:
        break;
    }

    final type = loadout[index];
    _showTip(type);
    if (type.input == BoosterInput.instant) {
      return _fire(index, const BoosterTarget.instant());
    }
    // Tapping another slot while armed switches the armed booster (§4.3).
    _armedIndex = index;
    _aimRemaining = _aimSeconds;
    _aim = null;
    _preview = const [];
    _previewValid = false;
    engine.boosterAimHold = true;
    _pendingArmed = BoosterArmedEvent(type);
    notifyListeners();
    return true;
  }

  BoosterArmedEvent? _pendingArmed;

  /// Picked up by [TetrofallGame] on the next tick, so arming and cancelling
  /// reach the render layer through the same event stream every other change
  /// to the board does.
  BoosterArmedEvent? takePendingArmed() {
    final event = _pendingArmed;
    _pendingArmed = null;
    return event;
  }

  /// The finger moved over the board while a booster is armed. Recomputes
  /// exactly what would go, so the outline can never promise more than the
  /// effect delivers (§4.4).
  void updateAim(int row, int col, {double dragCells = 0}) {
    final index = _armedIndex;
    final loadout = _loadout;
    if (index == null || loadout == null) return;
    final type = loadout[index];
    final target = _targetFor(type, row, col, dragCells);
    _aim = target;
    _preview = engine.boosterPreview(type, target);
    _previewValid = engine.canUseBooster(type, target);
    notifyListeners();
  }

  BoosterTarget _targetFor(
    BoosterType type,
    int row,
    int col,
    double dragCells,
  ) => switch (type.input) {
    BoosterInput.aimCell => BoosterTarget.cell(row, col),
    BoosterInput.aimRow => BoosterTarget.row(row),
    BoosterInput.aimColumn => BoosterTarget.column(col),
    BoosterInput.aimRowSwipe =>
      dragCells.abs() >= BoosterTuning.slideMinDragCells
          ? BoosterTarget.rowSwipe(
              row,
              dragCells < 0 ? BoosterDirection.left : BoosterDirection.right,
            )
          : BoosterTarget.row(row),
    BoosterInput.swipeDirection =>
      dragCells.abs() >= BoosterTuning.slideMinDragCells
          ? BoosterTarget.swipe(
              dragCells < 0 ? BoosterDirection.left : BoosterDirection.right,
            )
          : const BoosterTarget.instant(),
    BoosterInput.instant => const BoosterTarget.instant(),
  };

  /// The finger lifted. Fires if the target is good, and shakes and stays
  /// armed if it is not — the charge is never spent on a miss (§4.3).
  bool releaseAim() {
    final index = _armedIndex;
    final loadout = _loadout;
    if (index == null || loadout == null) return false;
    final type = loadout[index];
    final target = _aim;
    if (target == null || !engine.canUseBooster(type, target)) {
      _shakeToken++;
      notifyListeners();
      return false;
    }
    return _fire(index, target);
  }

  bool _fire(int index, BoosterTarget target) {
    final loadout = _loadout;
    if (loadout == null) return false;
    final type = loadout[index];
    _showTip(type);
    if (!engine.useBooster(type, target)) {
      _shakeToken++;
      notifyListeners();
      return false;
    }
    _charges[index]--;
    _clearAim();
    notifyListeners();
    return true;
  }

  void cancelAim(BoosterCancelReason reason) {
    if (_armedIndex == null) return;
    _clearAim();
    notifyListeners();
  }

  void _clearAim() {
    _armedIndex = null;
    _aim = null;
    _preview = const [];
    _previewValid = false;
    _aimRemaining = 0;
    engine.boosterAimHold = false;
    _pendingArmed = const BoosterArmedEvent(null);
  }

  // --- rewarded refill (§4.9) --------------------------------------------

  /// Whether tapping [index] should open the refill sheet rather than arm
  /// anything. Only in `playing`, and never while another booster is armed —
  /// two ad offers must never compete for the same moment.
  bool offersRefill(int index) =>
      engine.phase == GamePhase.playing &&
      _armedIndex == null &&
      stateAt(index) == BoosterSlotState.spent;

  /// The video completed. A refilled charge is an ordinary charge: it arms,
  /// fires and resolves exactly like the first one (§4.9 rule 5).
  void grantRefill(int index) {
    if (!canRefillAt(index)) return;
    _charges[index] = BoosterTuning.chargesPerBooster;
    _refills[index]++;
    _refillsThisRun++;
    notifyListeners();
  }

  // --- tips (§4.8) --------------------------------------------------------

  void _showTip(BoosterType type) {
    if (!_tipped.add(type)) return;
    _tip = type.tip;
    _tipRemaining = BoosterTuning.tipDuration.inMilliseconds / 1000;
  }

  /// Driven from the game loop. Ages the aim window and the tip, and repaints
  /// the bar when — and only when — one of the four slots would now draw
  /// differently.
  void tick(double dt) {
    var changed = false;

    if (_tipRemaining > 0) {
      _tipRemaining -= dt;
      if (_tipRemaining <= 0) {
        _tip = null;
        changed = true;
      }
    }

    if (_armedIndex != null) {
      // A tip pauses the window rather than eating it: the first time a
      // booster is armed, reading the line is not aiming time (§4.8).
      if (_tipRemaining <= 0) _aimRemaining -= dt;
      changed = true;
      if (_aimRemaining <= 0) _clearAim();
    }

    // "No target" is recomputed from the grid every frame for instant
    // boosters (§4.2) — a few hundred cell reads on an 18x32 grid — but the
    // bar is only told when the answer changes, so a steady board costs one
    // scan a frame and no rebuilds.
    if (_loadout != null) {
      final signature = _signature();
      if (signature != _lastSignature) {
        _lastSignature = signature;
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  String? _lastSignature;

  String _signature() {
    final buffer = StringBuffer();
    for (var i = 0; i < _charges.length; i++) {
      buffer
        ..write(stateAt(i).index)
        ..write(':')
        ..write(_charges[i])
        ..write('|');
    }
    return buffer.toString();
  }
}

enum BoosterCancelReason { tap, timeout, pause, back }
