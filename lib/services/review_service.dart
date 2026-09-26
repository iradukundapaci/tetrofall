import 'package:in_app_review/in_app_review.dart';

import 'analytics_service.dart' show logAnalyticsFailure;
import 'crash_reporting.dart';
import 'remote_flags.dart';
import 'run_summary.dart';
import 'session_tracker.dart';
import 'storage_service.dart';
import 'telemetry.dart';

/// The store's rating prompt, behind an interface so the rules that decide
/// *when* to ask can be exercised without a store behind them.
abstract class ReviewService {
  Future<bool> isAvailable();

  /// Asks the store to show its in-app rating card. The store decides whether
  /// it actually appears (Google enforces a quota nobody can read), and the app
  /// is never told whether the player rated. Safe to call at every trigger.
  Future<void> requestReview();

  /// Opens the game's store page directly. No quota; fine to call any time.
  Future<void> openStoreListing();
}

class InAppReviewService implements ReviewService {
  final InAppReview _review = InAppReview.instance;

  @override
  Future<bool> isAvailable() => _review.isAvailable();

  @override
  Future<void> requestReview() => _review.requestReview();

  @override
  Future<void> openStoreListing() => _review.openStoreListing();
}

/// Why the player might be happy right now.
enum ReviewTrigger {
  newBest('new_best'),
  longRun('long_run'),
  comeback('comeback'),
  bigMoment('big_moment');

  const ReviewTrigger(this.id);
  final String id;
}

/// The rules for asking, kept apart from anything that touches a store.
///
/// The store's own guidelines shape them: no question before the prompt ("do
/// you like the game?") so that only happy people see it, no reward for
/// rating, and never over gameplay.
abstract final class ReviewPolicy {
  static const minSessions = 3;
  static const minDaysSinceInstall = 2;
  static const minDaysBetweenRequests = 30;
  static const maxRequestsPerYear = 3;
  static const minSessionSeconds = 60;
  static const longRunSeconds = 180.0;

  /// Whether the *timing* allows asking at all, whatever the player just did.
  static bool mayAsk({
    required int sessionCount,
    required int daysSinceInstall,
    required List<DateTime> previousRequests,
    required Duration sessionElapsed,
    required bool crashedThisSession,
    required DateTime now,
  }) {
    if (sessionCount < minSessions) return false;
    if (daysSinceInstall < minDaysSinceInstall) return false;
    if (crashedThisSession) return false;
    if (sessionElapsed.inSeconds < minSessionSeconds) return false;

    if (previousRequests.isNotEmpty) {
      final last = previousRequests.reduce((a, b) => a.isAfter(b) ? a : b);
      if (now.difference(last).inDays < minDaysBetweenRequests) return false;
    }
    final inLastYear = previousRequests
        .where((t) => now.difference(t).inDays < 365)
        .length;
    return inLastYear < maxRequestsPerYear;
  }

  /// The good thing that happened *during* the run, if any. An endless run
  /// always ends in a top-out, so the ending itself is never the reason.
  ///
  /// [recentScores] are the player's previous runs, oldest first.
  static ReviewTrigger? happyMoment(
    EndlessRunSummary run, {
    required List<int> recentScores,
  }) {
    final beatsMedian = run.score > _median(recentScores);

    if (run.isNewBest && run.bestBefore > 0) return ReviewTrigger.newBest;
    if (run.rescuesSurvived > 0 && beatsMedian) return ReviewTrigger.comeback;
    if ((run.tetrofalls > 0 || run.maxChain >= 4) && beatsMedian) {
      return ReviewTrigger.bigMoment;
    }
    if (run.durationSeconds >= longRunSeconds) return ReviewTrigger.longRun;
    return null;
  }

  static double _median(List<int> scores) {
    if (scores.isEmpty) return 0;
    final sorted = [...scores]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// Applies [ReviewPolicy] to a finished run and, when everything lines up,
/// asks the store.
class ReviewPrompter {
  ReviewPrompter({required this.storage, ReviewService? service})
    : service = service ?? InAppReviewService();

  final StorageService storage;
  final ReviewService service;

  /// Call from the game-over screen — a calm moment — with the run that just
  /// ended and the scores *before* it. Returns the trigger if the store was
  /// asked, null otherwise.
  Future<ReviewTrigger?> maybeAsk(
    EndlessRunSummary run, {
    required List<int> recentScores,
    DateTime? now,
  }) async {
    if (!RemoteFlags.reviewPromptEnabled) return null;
    final when = now ?? DateTime.now();

    final allowed = ReviewPolicy.mayAsk(
      sessionCount: storage.sessionCount,
      daysSinceInstall: storage.daysSinceInstall(when),
      previousRequests: storage.reviewRequestTimes,
      sessionElapsed: SessionTracker.elapsed,
      crashedThisSession: CrashReporting.crashedThisSession,
      now: when,
    );
    if (!allowed) return null;

    final trigger = ReviewPolicy.happyMoment(run, recentScores: recentScores);
    if (trigger == null) return null;

    try {
      if (!await service.isAvailable()) return null;
      // Recorded before asking: the store may show nothing, but our own
      // spacing must hold either way.
      await storage.addReviewRequest(when);
      Telemetry.reviewRequest(trigger.id);
      await service.requestReview();
      return trigger;
    } catch (error) {
      logAnalyticsFailure('requesting a review', error);
      return null;
    }
  }
}
