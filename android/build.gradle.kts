// android/build.gradle.kts
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import com.android.build.gradle.LibraryExtension

buildscript {
    repositories {
        google()
        mavenCentral()
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // ✅ Force Kotlin to use Java 17
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }

    // ✅ Force Java to use Java 17
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
        options.compilerArgs.add("-Xlint:-options")
    }
}

// ✅ Redirect build output
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")

    // ✅ Apply JVM 17 config again for submodules/plugins
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
        options.compilerArgs.add("-Xlint:-options")
    }
}

// ✅ Fix: give a namespace to old plugins that don't declare one.
// AGP 8 requires every Android library to set `namespace`; older plugins (e.g.
// flutter_keyboard_visibility 5.4.1, pulled in by flutter_typeahead) only have
// the legacy `package` attribute in their AndroidManifest.xml. Reuse that value.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            if (namespace == null) {
                val manifest = file("src/main/AndroidManifest.xml")
                val pkg = if (manifest.exists()) {
                    Regex("""package\s*=\s*"([^"]+)"""").find(manifest.readText())?.groupValues?.get(1)
                } else null
                namespace = pkg ?: "dev.flutter.plugins.${project.name.replace('-', '_')}"
            }
        }
    }
}

// ✅ Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// ✅ Force all Android modules to use Java 17
gradle.afterProject {
    if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            compileOptions.targetCompatibility = JavaVersion.VERSION_17
        }

        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
    }
}

// ✅ Fix: Force SDK + Java level for document_scanner_flutter plugin
subprojects {
    if (project.name == "document_scanner_flutter") {
        project.afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                val androidExt = ext as LibraryExtension
                androidExt.compileSdk = 34
                androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}
