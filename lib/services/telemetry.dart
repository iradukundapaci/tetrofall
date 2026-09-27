import 'analytics_service.dart';
import 'firebase_analytics_service.dart';
import 'run_summary.dart';

/// Every product event, defined once and fanned out to both analytics SDKs so
/// names and parameters can't drift.
///
///  * **GameAnalytics** gets a design event id (`a:b:c`, fixed vocabulary, at
///    most five parts) with any number in its value.
///  * **Firebase** gets a snake_case event name (at most 40 characters, at most
///    25 parameters) with its parameters.
///
/// Nothing personal is carried. Calls are inert until the services are ready
/// and never throw.
abstract final class Telemetry {
  static const mode = 'endless';

  static void sessionStart({required int index}) {
    _send(
      firebase: 'session_start_game',
      params: {'session_index': index},
      design: 'session:start',
      value: index.toDouble(),
    );
  }

  static void sessionEnd({required int index, required int durationSeconds}) {
    _send(
      firebase: 'session_end_game',
      params: {'session_index': index, 'duration_s': durationSeconds},
      design: 'session:end',
      value: durationSeconds.toDouble(),
    );
  }

  static void endlessStart({
    required String skillBucket,
    required bool directorOn,
    required int runIndex,
  }) {
    _send(
      firebase: 'endless_start',
      params: {
        'mode': mode,
        'skill_bucket': skillBucket,
        'director': directorOn ? 'on' : 'off',
        'run_index': runIndex,
      },
      design: 'endless:start:${directorOn ? 'on' : 'off'}',
      value: runIndex.toDouble(),
    );
  }

  static void endlessEnd(EndlessRunSummary s) {
    _send(
      firebase: 'endless_end',
      params: {
        'mode': mode,
        'score': s.score,
        'duration_s': s.durationSeconds.round(),
        'lines': s.lines,
        'max_chain': s.maxChain,
        'tetrofalls': s.tetrofalls,
        'death': s.deathReason,
        'rescues': s.rescues,
        'rescues_survived': s.rescuesSurvived,
        'comebacks': s.comebacks,
        'gift_rows': s.giftRows,
        'bag_bias_picks': s.bagBiasPicks,
        'is_best': s.isNewBest ? 1 : 0,
        'continue_used': s.continuesUsed,
        'skill_bucket': s.skillBucket,
        'director': s.directorOn ? 'on' : 'off',
        if (s.placementQuality != null)
          'placement_quality': (s.placementQuality! * 100).round(),
      },
      design: 'endless:end:${s.deathReason}',
      value: s.score.toDouble(),
    );
    // Duration as its own number, for median-run-length dashboards.
    AnalyticsService.design(
      'endless:duration:${s.skillBucket}',
      value: s.durationSeconds,
    );
  }

  static void directorRescue({
    required double stress,
    required bool survived,
    required bool comeback,
  }) {
    _send(
      firebase: 'director_rescue',
      params: {
        'stress': (stress * 100).round(),
        'survived': survived ? 1 : 0,
        'comeback': comeback ? 1 : 0,
      },
      design: 'director:rescue:${survived ? 'survived' : 'failed'}',
      value: stress,
    );
  }

  /// Sampled by the caller; phases change every ~15 seconds.
  static void directorPhase(String phase) {
    _send(
      firebase: 'director_phase',
      params: {'phase': phase},
      design: 'director:phase:$phase',
    );
  }

  /// Records only that the prompt was requested; the OS decides whether it
  /// shows.
  static void reviewRequest(String trigger) {
    _send(
      firebase: 'review_request',
      params: {'trigger': trigger},
      design: 'review:request:$trigger',
    );
  }

  static void feedbackSent(String category) {
    _send(
      firebase: 'feedback_sent',
      params: {'category': category, 'mode': mode},
      design: 'feedback:sent:$category',
    );
  }

  static void setSkillBucket(String bucket) {
    FirebaseAnalyticsService.setUserProperty('skill_bucket', bucket);
    AnalyticsService.setSkillBucketDimension(bucket);
  }

  static void setExperiment(String name) {
    FirebaseAnalyticsService.setUserProperty('experiment', name);
  }

  static void _send({
    required String firebase,
    required Map<String, Object> params,
    required String design,
    double? value,
  }) {
    FirebaseAnalyticsService.logEvent(firebase, params);
    AnalyticsService.design(design, value: value);
  }
}
