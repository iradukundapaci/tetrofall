import 'package:in_app_review/in_app_review.dart';

import 'analytics_service.dart' show logAnalyticsFailure;
import 'crash_reporting.dart';
import 'remote_flags.dart';
import 'run_summary.dart';
import 'session_tracker.dart';
import 'storage_service.dart';
import 'telemetry.dart';

/// The store's rating prompt, behind an interface so the rules for *when* to
/// ask can be exercised without a store.
abstract class ReviewService {
  Future<bool> isAvailable();

  /// Asks the store to show its rating card. The store decides whether it
  /// appears (there is an unreadable quota), so this is safe to call at every
  /// trigger.
  Future<void> requestReview();

  /// Opens the store page directly; no quota.
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

/// The rules for asking, kept apart from the store. Shaped by store
/// guidelines: no "do you like the game?" gate, no reward for rating, never
/// over gameplay.
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

  /// The good thing that happened during the run, if any (the ending never
  /// counts). [recentScores] are previous runs, oldest first.
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

/// Applies [ReviewPolicy] to a finished run and asks the store when it allows.
class ReviewPrompter {
  ReviewPrompter({required this.storage, ReviewService? service})
    : service = service ?? InAppReviewService();

  final StorageService storage;
  final ReviewService service;

  /// Call from the game-over screen with the run and the scores before it.
  /// Returns the trigger if the store was asked.
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
      // Recorded first: the store may show nothing but our spacing must hold.
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
