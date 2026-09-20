allprojects {
    repositories {
        google()
        mavenCentral()
        // The GameAnalytics Android SDK is published from GameAnalytics' own
        // Maven, not Central. The gameanalytics_sdk plugin declares this repo
        // in its build.gradle too, but that block loses to this one: this root
        // project is evaluated first and its repositories are what the plugin
        // subproject's classpath resolves against, so without the line here
        // `:app:mergeReleaseNativeLibs` fails to find gameanalytics-android.
        maven { url = uri("https://maven.gameanalytics.com/release") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// gameanalytics_sdk is compiled against android-33, and AGP 9 resolves the
// AndroidX it pulls in (fragment 1.7.1, window 1.2.0, ...) to versions that
// require 34 or later, so `checkReleaseAarMetadata` fails the whole release
// build. The plugin is already at its latest release, so there is no upgrade to
// take; this raises only its compileSdk.
//
// compileSdk is not targetSdk: it changes which APIs the plugin's own code may
// call, not how the app behaves at runtime, so nothing here moves the Play
// compliance surface pinned in app/build.gradle.kts.
//
// Scoped to that one module on purpose. A blanket override across every
// subproject would also quietly mask the next plugin that falls behind, which
// is a failure worth seeing. Remove this when gameanalytics_sdk ships a
// compileSdk of 34+.
subprojects {
    if (name == "gameanalytics_sdk") {
        afterEvaluate {
            extensions.findByName("android")?.let { android ->
                (android as com.android.build.gradle.LibraryExtension).compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
