import 'dart:math';

import 'package:flutter/foundation.dart';

import '../game/boosters/booster_type.dart';
import '../game/config/economy_tuning.dart';
import '../game/engine/events.dart';
import 'mystery_chest.dart';
import 'storage_service.dart';
import 'wallet_service.dart';

/// What a day of the login calendar pays.
class LoginReward {
  const LoginReward.coins(int this.coins) : charge = null, chest = false;
  const LoginReward.charge(BoosterType this.charge)
    : coins = null,
      chest = false;
  const LoginReward.chest() : coins = null, charge = null, chest = true;

  final int? coins;
  final BoosterType? charge;
  final bool chest;

  String get label {
    if (coins != null) return '$coins Coins';
    if (chest) return 'Mystery Chest';
    return '${charge!.displayName} x1';
  }
}

enum ChallengeKind { clearRows, reachChain, fireBoosters, finishRuns }

/// One of today's three challenges.
class DailyChallenge {
  DailyChallenge(
    this.kind,
    this.target, {
    this.progress = 0,
    this.claimed = false,
  });

  final ChallengeKind kind;
  final int target;
  int progress;
  bool claimed;

  bool get complete => progress >= target;

  String get label => switch (kind) {
    ChallengeKind.clearRows => 'Clear $target rows',
    ChallengeKind.reachChain => 'Reach a chain of $target',
    ChallengeKind.fireBoosters => 'Use $target boosters',
    ChallengeKind.finishRuns => 'Finish $target runs',
  };

  String encode() => '${kind.name}:$target:$progress:${claimed ? 1 : 0}';

  static DailyChallenge? decode(String s) {
    final p = s.split(':');
    if (p.length != 4) return null;
    final kind = ChallengeKind.values.where((k) => k.name == p[0]).firstOrNull;
    final target = int.tryParse(p[1]);
    final progress = int.tryParse(p[2]);
    if (kind == null || target == null || progress == null) return null;
    return DailyChallenge(
      kind,
      target,
      progress: progress,
      claimed: p[3] == '1',
    );
  }
}

/// The login calendar and the daily challenges.
///
/// These are the zero-ad floor of the economy: a player who never watches
/// anything still earns here, so the game is slower without ads but never
/// stuck — which also covers the player whose ads simply do not fill. They are
/// kept deliberately below what a day of ad views pays, or the faucet would be
/// free and nobody would watch anything.
class DailyService extends ChangeNotifier {
  DailyService(this._storage, this._wallet, this._chest) {
    _loadChallenges();
  }

  final StorageService _storage;
  final WalletService _wallet;
  final MysteryChest _chest;

  /// Seven days, matching `screens/daily-reward.html`: Coins on days 1, 3 and
  /// 6 (from [EconomyTuning.loginStreakCoins]), a booster charge on 2, 4 and
  /// 5, and the Mystery Chest on 7.
  static const _chargeDays = <int, BoosterType>{
    2: BoosterType.bomb,
    4: BoosterType.drill,
    5: BoosterType.lightning,
  };

  static LoginReward rewardForDay(int day) {
    if (day == 7) return const LoginReward.chest();
    final charge = _chargeDays[day];
    if (charge != null) return LoginReward.charge(charge);
    return LoginReward.coins(EconomyTuning.loginStreakCoins[day - 1]);
  }

  // --- Login calendar -----------------------------------------------------

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  bool get canClaimLogin {
    final last = _storage.dailyLastClaimAt;
    return last == null || _dayOf(last) != _dayOf(DateTime.now());
  }

  /// The day the next claim would pay. A missed day starts the calendar over,
  /// and finishing day 7 wraps back to day 1.
  int get nextLoginDay {
    final last = _storage.dailyLastClaimAt;
    final day = _storage.dailyStreakDay;
    if (last == null || day == 0) return 1;
    final today = _dayOf(DateTime.now());
    final gap = today.difference(_dayOf(last)).inDays;
    if (gap == 0) return day; // already claimed today
    if (gap > 1 || day >= 7) return 1;
    return day + 1;
  }

  /// The last day claimed, for drawing the calendar's checked cells.
  int get claimedThroughDay =>
      canClaimLogin ? nextLoginDay - 1 : _storage.dailyStreakDay;

  /// Pays today's reward. Returns what it paid, plus the chest's contents on
  /// day 7, or null if today is already claimed.
  Future<(LoginReward, ChestReward?)?> claimLogin() async {
    if (!canClaimLogin) return null;
    final day = nextLoginDay;
    final reward = rewardForDay(day);
    ChestReward? chest;
    if (reward.coins != null) {
      await _wallet.earn(reward.coins!);
    } else if (reward.charge != null) {
      await _wallet.grantCharges(reward.charge!);
    } else {
      chest = await _chest.open();
    }
    await _storage.setDailyStreakDay(day);
    await _storage.setDailyLastClaimAt(DateTime.now());
    notifyListeners();
    return (reward, chest);
  }

  // --- Challenges ---------------------------------------------------------

  late int _challengeDay;
  late List<DailyChallenge> _challenges;

  List<DailyChallenge> get challenges {
    _rolloverIfNewDay();
    return _challenges;
  }

  /// Two sizes of each kind. Picked three a day, one per kind, so a day never
  /// asks for the same thing twice.
  static const _pool = <ChallengeKind, List<int>>{
    ChallengeKind.clearRows: [20, 50],
    ChallengeKind.reachChain: [3, 5],
    ChallengeKind.fireBoosters: [3, 6],
    ChallengeKind.finishRuns: [3, 5],
  };

  static int _dayNumber(DateTime t) =>
      _dayOf(t).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// Seeded by the date, so today's challenges are the same across restarts
  /// without having to be stored before the first one is touched.
  static List<DailyChallenge> _roll(int day) {
    final rng = Random(day);
    final kinds = [...ChallengeKind.values]..shuffle(rng);
    return [
      for (final kind in kinds.take(EconomyTuning.dailyChallengesPerDay))
        DailyChallenge(kind, _pool[kind]![rng.nextInt(_pool[kind]!.length)]),
    ];
  }

  void _loadChallenges() {
    final today = _dayNumber(DateTime.now());
    final stored = _storage.dailyChallengeState?.split('|');
    if (stored != null &&
        stored.length == 2 &&
        int.tryParse(stored[0]) == today) {
      final decoded = stored[1]
          .split(';')
          .map(DailyChallenge.decode)
          .nonNulls
          .toList();
      if (decoded.length == EconomyTuning.dailyChallengesPerDay) {
        _challengeDay = today;
        _challenges = decoded;
        return;
      }
    }
    _challengeDay = today;
    _challenges = _roll(today);
  }

  void _rolloverIfNewDay() {
    if (_dayNumber(DateTime.now()) != _challengeDay) {
      _loadChallenges();
      notifyListeners();
    }
  }

  Future<void> _persistChallenges() => _storage.setDailyChallengeState(
    '$_challengeDay|${_challenges.map((c) => c.encode()).join(';')}',
  );

  /// Whether the next chain event belongs to the continue's forced sweep.
  bool _lastClearForced = false;

  /// Fed every engine event of a real run by the gameplay screen — never the
  /// menu demo or the tutorial, which are not the player's achievements.
  void onEvent(GameEvent event) {
    switch (event) {
      case RowsClearedEvent(:final rows, :final forced):
        // The continue's board wipe shatters like a clear, but the player did
        // not do it (`events.dart`), so it counts for nothing here.
        _lastClearForced = forced;
        if (!forced) _advance(ChallengeKind.clearRows, add: rows.length);
      case ChainAdvancedEvent(:final chainIndex):
        if (!_lastClearForced) {
          _advance(ChallengeKind.reachChain, reach: chainIndex + 1);
        }
      case BoosterFiredEvent():
        _advance(ChallengeKind.fireBoosters, add: 1);
      case GameOverEvent():
        _advance(ChallengeKind.finishRuns, add: 1);
      default:
        break;
    }
  }

  void _advance(ChallengeKind kind, {int add = 0, int? reach}) {
    _rolloverIfNewDay();
    var changed = false;
    for (final c in _challenges) {
      if (c.kind != kind || c.complete) continue;
      final next = reach != null ? max(c.progress, reach) : c.progress + add;
      final clamped = min(next, c.target);
      if (clamped != c.progress) {
        c.progress = clamped;
        changed = true;
      }
    }
    if (!changed) return;
    _persistChallenges();
    notifyListeners();
  }

  int get claimableChallenges =>
      challenges.where((c) => c.complete && !c.claimed).length;

  Future<bool> claimChallenge(DailyChallenge challenge) async {
    if (!challenge.complete || challenge.claimed) return false;
    challenge.claimed = true;
    await _persistChallenges();
    await _wallet.earn(EconomyTuning.dailyChallengeReward);
    notifyListeners();
    return true;
  }

  /// Something to claim right now — drives the menu badge.
  bool get hasSomethingToClaim => canClaimLogin || claimableChallenges > 0;
}
