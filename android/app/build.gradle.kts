plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Required to process google-services.json for Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.zanzo"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    defaultConfig {
        applicationId = "com.example.zanzo"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Using debug key for now so flutter run --release works
            signingConfig = signingConfigs.getByName("debug")

            // ✅ Enable R8 with custom rules
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

tasks.withType<Exec>().configureEach {
    if (commandLine.any { it.contains("flutter") }) {
        commandLine = listOf("/usr/local/bin/flutter") + commandLine.drop(1)
        environment("PATH", "/usr/local/bin:" + System.getenv("PATH"))
    }
}