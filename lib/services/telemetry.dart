import 'analytics_service.dart';
import 'firebase_analytics_service.dart';
import 'run_summary.dart';

/// Every product event, defined once and fanned out to both analytics SDKs, so
/// a name or a parameter can never drift between them.
///
///  * **GameAnalytics** gets a design event id (`a:b:c`, fixed vocabulary, at
///    most five parts) with any number in its value.
///  * **Firebase** gets a snake_case event name (at most 40 characters, at most
///    25 parameters) with its parameters.
///
/// Nothing here carries anything personal: no name, no email. Like the two
/// services underneath it, every call is inert until they are ready and never
/// throws.
abstract final class Telemetry {
  static const mode = 'endless';

  // ---------------------------------------------------------------- session

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

  static void modeSelect(String selected) {
    _send(
      firebase: 'mode_select',
      params: {'mode': selected},
      design: 'mode:select:$selected',
    );
  }

  // ---------------------------------------------------------------- endless

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
        'gift_rows': s.giftRows,
        'bag_bias_picks': s.bagBiasPicks,
        'is_best': s.isNewBest ? 1 : 0,
        'continue_used': s.continuesUsed,
        'skill_bucket': s.skillBucket,
        'director': s.directorOn ? 'on' : 'off',
      },
      design: 'endless:end:${s.deathReason}',
      value: s.score.toDouble(),
    );
    // Median-run-length dashboards want the duration as its own number.
    AnalyticsService.design(
      'endless:duration:${s.skillBucket}',
      value: s.durationSeconds,
    );
  }

  // ---------------------------------------------------------------- director

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

  /// Sampled by the caller; a phase changes every ~15 seconds and reporting
  /// every one would drown the dashboard.
  static void directorPhase(String phase) {
    _send(
      firebase: 'director_phase',
      params: {'phase': phase},
      design: 'director:phase:$phase',
    );
  }

  // ---------------------------------------------------------------- rating

  /// The OS decides whether the prompt actually shows, and the app is never
  /// told; this only records that it was asked.
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

  // ---------------------------------------------------------------- who

  static void setSkillBucket(String bucket) {
    FirebaseAnalyticsService.setUserProperty('skill_bucket', bucket);
    AnalyticsService.setSkillBucketDimension(bucket);
  }

  static void setExperiment(String name) {
    FirebaseAnalyticsService.setUserProperty('experiment', name);
  }

  // ---------------------------------------------------------------- plumbing

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
