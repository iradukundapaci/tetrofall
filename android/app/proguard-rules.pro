# R8 / ProGuard keep rules for the release build.
#
# Deliberately empty. The Flutter Gradle plugin contributes the engine's rules,
# and google_mobile_ads, shared_preferences and audioplayers each ship consumer
# rules inside their AARs, so nothing here is needed to build.
#
# Add rules only when R8 demonstrably breaks something at RUNTIME — a release
# build that works in debug and crashes when minified. The usual suspects for
# this app, in the order they are worth checking (android_release_plan.md §5.2):
#
#   * google_mobile_ads — reflection over ad-format classes
#   * flame_audio / audioplayers — native player lookup
#   * shared_preferences — the platform channel codec
#   * firebase_analytics — the measurement SDK ships its own consumer
#     rules, so this is here only as the next place to look
#
# When you do add a rule, say WHICH symptom it fixes. An unexplained -keep is
# impossible to remove later, and they accumulate until minification does
# nothing.

# GameAnalytics. The release build runs R8 with `isShrinkResources`, and the
# SDK is reached reflectively from its own native layer — without these the
# APK builds clean and then reports nothing.
-keep class com.gameanalytics.sdk.** { *; }
-dontwarn com.gameanalytics.sdk.**

# OkHttp, brought in by the Liftoff (Vungle) SDK. It probes for optional TLS
# providers — BouncyCastle, Conscrypt, OpenJSSE — and falls back to the
# platform's own when they are absent, which they are here. R8 fails the
# release build on the missing classes without these. They are OkHttp's own
# documented rules; newer OkHttp releases ship them inside the AAR.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
