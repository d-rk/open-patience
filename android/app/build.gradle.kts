import java.util.Properties
import java.io.FileInputStream
import com.android.build.gradle.internal.api.ApkVariantOutputImpl

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val testingKeystorePropertiesFile = rootProject.file("key.testing.properties")
val testingKeystoreProperties = Properties()
val hasTestingKeystore = testingKeystorePropertiesFile.exists()
if (hasTestingKeystore) {
    testingKeystoreProperties.load(FileInputStream(testingKeystorePropertiesFile))
}

android {
    namespace = "io.github.d_rk.openpatience"
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
        applicationId = "io.github.d_rk.openpatience"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
        if (hasTestingKeystore) {
            create("testing") {
                keyAlias = testingKeystoreProperties["keyAlias"] as String
                keyPassword = testingKeystoreProperties["keyPassword"] as String
                storeFile = file(testingKeystoreProperties["storeFile"] as String)
                storePassword = testingKeystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // signingConfig is assigned per-flavor below, so production and
            // testing sign with different keys. (A signingConfig set here
            // would take precedence over the flavor's and defeat that.)
        }
    }

    flavorDimensions += "channel"

    productFlavors {
        create("production") {
            dimension = "channel"
            manifestPlaceholders["appLabel"] = "Open Patience"
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No key.properties (local dev) — fall back to debug signing
                // so `flutter run --release` still works.
                signingConfigs.getByName("debug")
            }
        }
        // Named "Testing" (capital T), not "testing": AGP hard-rejects any
        // product flavor whose name starts with the lowercase prefix "test"
        // ("ProductFlavor names cannot start with 'test'" — reserved for its
        // own generated test source sets/tasks). The capital-T variant still
        // satisfies `flutter build apk --flavor testing` and
        // `--flavor Testing` on the CLI, since Flutter capitalizes the first
        // letter it's given before mapping to the Gradle task name
        // (assembleTestingRelease either way).
        create("Testing") {
            dimension = "channel"
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "Open Patience (Testing)"
            signingConfig = if (hasTestingKeystore) {
                signingConfigs.getByName("testing")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// ABI-split versionCode scheme (required by F-Droid for per-architecture APKs):
// each split APK gets versionCode = base * 10 + abi, so a single upstream
// versionCode fans out to unique, ordered per-ABI codes. Only fires when an
// output carries an ABI filter (i.e. `--split-per-abi`); a universal build —
// like the self-hosted repo's — has no ABI filter and keeps its base code.
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode =
            abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride =
                variant.versionCode * 10 + abiVersionCode
        }
    }
}

flutter {
    source = "../.."
}
