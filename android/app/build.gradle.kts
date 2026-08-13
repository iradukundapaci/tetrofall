import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
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

flutter {
    source = "../.."
}
