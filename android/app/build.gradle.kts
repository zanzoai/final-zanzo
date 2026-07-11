import java.util.Properties

// ---------------------------------------------------------------------------
// Upload-keystore signing
// Release signing is loaded from android/key.properties (git-ignored).
// Copy android/key.properties.template → android/key.properties and fill in
// all four fields before building a release AAB.
// See LAUNCH_TRACKER.md for the keytool command to generate the keystore.
// ---------------------------------------------------------------------------
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().also { props ->
    if (keyPropertiesFile.exists()) keyPropertiesFile.inputStream().use { props.load(it) }
}
val releaseSigningReady: Boolean = keyPropertiesFile.exists() &&
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { keyProperties.getProperty(it)?.isNotBlank() == true }

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Required to process google-services.json for Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "ai.zanzo.app"
    compileSdk = 36
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    defaultConfig {
        applicationId = "ai.zanzo.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (releaseSigningReady) {
        signingConfigs {
            create("release") {
                storeFile     = file(keyProperties.getProperty("storeFile")!!)
                storePassword = keyProperties.getProperty("storePassword")!!
                keyAlias      = keyProperties.getProperty("keyAlias")!!
                keyPassword   = keyProperties.getProperty("keyPassword")!!
            }
        }
    }

    buildTypes {
        release {
            // Intentionally no debug-key fallback. When key.properties is absent
            // the task-level check below fires before any release task executes.
            signingConfig = if (releaseSigningReady) signingConfigs.getByName("release") else null

            isMinifyEnabled = true
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
}

// Provide a clear error before any release task executes if key.properties is
// missing or incomplete. Debug builds are unaffected — no "Release"-named
// task is scheduled during a debug invocation.
if (!releaseSigningReady) {
    tasks.configureEach {
        if (name.contains("Release", ignoreCase = true)) {
            doFirst {
                throw GradleException(
                    "\n\n" + "=".repeat(60) + "\n" +
                    "  RELEASE SIGNING NOT CONFIGURED\n" +
                    "=".repeat(60) + "\n" +
                    "  android/key.properties is missing or incomplete.\n\n" +
                    "  Steps:\n" +
                    "    1. Generate upload keystore (see LAUNCH_TRACKER.md)\n" +
                    "    2. cp android/key.properties.template \\\n" +
                    "          android/key.properties\n" +
                    "    3. Fill in storeFile, storePassword,\n" +
                    "       keyAlias, keyPassword\n\n" +
                    "  Debug builds are unaffected by this check.\n" +
                    "=".repeat(60) + "\n"
                )
            }
        }
    }
}

tasks.withType<Exec>().configureEach {
    if (commandLine.any { it.contains("flutter") }) {
        commandLine = listOf("/usr/local/bin/flutter") + commandLine.drop(1)
        environment("PATH", "/usr/local/bin:" + System.getenv("PATH"))
    }
}
