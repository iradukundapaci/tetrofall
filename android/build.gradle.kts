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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
