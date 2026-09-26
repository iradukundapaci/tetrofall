import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'analytics_service.dart' show logAnalyticsFailure;
import 'auth_service.dart';
import 'firebase_bootstrap.dart';
import 'run_summary.dart';
import 'telemetry.dart';

enum FeedbackCategory {
  bug('bug', 'Bug'),
  tooHard('too_hard', 'Too hard'),
  tooEasy('too_easy', 'Too easy'),
  idea('idea', 'Idea'),
  other('other', 'Other');

  const FeedbackCategory(this.id, this.label);
  final String id;
  final String label;
}

/// Sends a player's feedback to Firestore (`feedback/{autoId}`).
///
/// No email and no name: the document carries the anonymous uid, the app and
/// device, and optionally the stats of the last run. Rules only accept a
/// create from a signed-in user whose uid matches, and nothing can be read
/// back from the app — it is read in the Firebase console.
abstract final class FeedbackService {
  static const maxTextLength = 1000;

  /// True when the feedback was accepted. False means try again: offline, no
  /// Firebase, or the anonymous sign-in has not gone through.
  static Future<bool> send({
    required FeedbackCategory category,
    required String text,
    EndlessRunSummary? lastRun,
  }) async {
    await FirebaseBootstrap.init();
    if (!FirebaseBootstrap.isReady) return false;
    try {
      final uid = await AuthService.ensureAnonymous();
      if (uid == null) return false;

      final package = await PackageInfo.fromPlatform();
      final trimmed = text.trim();
      final data = <String, Object?>{
        'uid': uid,
        'category': category.id,
        'text': trimmed.length > maxTextLength
            ? trimmed.substring(0, maxTextLength)
            : trimmed,
        'appVersion': package.version,
        'buildNumber': package.buildNumber,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'deviceModel': await _deviceModel(),
        'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
        'mode': Telemetry.mode,
        'createdAt': FieldValue.serverTimestamp(),
        if (lastRun != null) ...{
          'lastScore': lastRun.score,
          'runSeconds': lastRun.durationSeconds.round(),
          'directorOn': lastRun.directorOn,
        },
      };

      await FirebaseFirestore.instance.collection('feedback').add(data);
      Telemetry.feedbackSent(category.id);
      return true;
    } catch (error) {
      logAnalyticsFailure('sending feedback', error);
      return false;
    }
  }

  static Future<String> _deviceModel() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) return (await info.androidInfo).model;
      if (Platform.isIOS) return (await info.iosInfo).utsname.machine;
    } catch (error) {
      logAnalyticsFailure('reading the device model', error);
    }
    return 'unknown';
  }
}
