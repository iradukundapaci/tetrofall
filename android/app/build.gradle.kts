import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing. `android/key.properties` is gitignored and holds the
// keystore passwords in plaintext; the keystore itself lives outside the repo.
// Copy android/key.properties.example to get started — Phase 2.1/2.2 of
// android_release_plan.md.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            FileInputStream(keystorePropertiesFile).use { load(it) }
        }
    }
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.nosleepstudios.tetrofall"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nosleepstudios.tetrofall"

        // Pinned rather than inherited from `flutter.*`. These match the
        // Flutter 3.44 defaults today, but they are a Play compliance surface,
        // not a toolchain detail: a Flutter upgrade must not be able to move
        // them without someone noticing.
        //
        // minSdk 24 (Android 7.0) is the Flutter default and covers >98% of
        // active devices; going lower buys nothing and costs testing.
        //
        // targetSdk 36 (Android 16) is what Play requires of new apps and
        // updates from 31 Aug 2026. This bar moves every August — re-check
        // Play Console -> Policy status before each submission.
        minSdk = 24
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Falling back keeps `flutter run --release` working for
                // anyone without the keystore, but a debug-signed artifact is
                // rejected by Play, so make it impossible to miss. Phase 5.2
                // verifies the shipped signature with `keytool -printcert`.
                logger.warn(
                    "\n" +
                        "╔════════════════════════════════════════════════════════════════╗\n" +
                        "║  WARNING: no android/key.properties — signing RELEASE with the ║\n" +
                        "║  DEBUG key. This artifact CANNOT be uploaded to Google Play.    ║\n" +
                        "║  See android/key.properties.example.                            ║\n" +
                        "╚════════════════════════════════════════════════════════════════╝\n",
                )
                signingConfig = signingConfigs.getByName("debug")
            }

            // R8. Classically the source of "works in debug, crashes in
            // release" — smoke-test ads, audio and shared_preferences on a
            // real device before shipping, and add keep rules to
            // proguard-rules.pro if anything breaks (Phase 5.2).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Top-level rather than inside `android {}`: AGP 9 removes `kotlinOptions` from
// the Android extension, and this is the form Flutter's own app template uses.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// AdMob mediation adapters. The ad sources are configured in the AdMob
// console, but they only bid once their adapter is in the binary — without
// these every mediation group serves Google demand alone.
//
// The gma_mediation_* Flutter plugins in pubspec.yaml already bring each
// adapter in, on both platforms. These lines only raise the Android ones to
// newer patch releases than the plugins pin (Gradle resolves to the highest),
// and match the Unity SDK to its adapter — the plugin pairs adapter 4.20 with
// SDK 4.17. When the plugins catch up, this block can go.
//
// Each adapter is built against a specific Google Mobile Ads SDK. All of the
// versions below pin play-services-ads 25.4.0, which is what
// google_mobile_ads 9.1.0 brings in; bump them together with the plugin, and
// check each adapter's POM when you do.
//
// AppLovin is deliberately absent until the account is approved — an adapter
// with no live mapping behind it is only APK weight.
//
// Meta Audience Network and InMobi are absent too, for now. Meta's property is
// not allow-listed for bidding, so it wins auctions and then returns no fill,
// which blocks every network behind it; InMobi never filled. Add
// gma_mediation_meta / gma_mediation_inmobi back to pubspec.yaml (and their
// adapters here, if you want the newer patch releases) once each network
// passes a single-source test in Google's Ad Inspector (re-add a temporary
// MobileAds.instance.openAdInspector call to reach it).
dependencies {
    // Unity Ads. The adapter does not pull the SDK in transitively.
    implementation("com.unity3d.ads:unity-ads:4.20.1")
    implementation("com.google.ads.mediation:unity:4.20.1.0")

    // Liftoff Monetize (Vungle)
    implementation("com.google.ads.mediation:vungle:7.7.8.1")
}

flutter {
    source = "../.."
}
