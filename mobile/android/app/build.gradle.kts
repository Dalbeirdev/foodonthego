plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.foodonthego.foodonthego"

    // Pinned rather than left on flutter.compileSdkVersion (36 for Flutter
    // 3.47.2). flutter_secure_storage 11 compiles against SDK 37 and its AAR
    // metadata requires consumers to do the same, so the debug build fails at
    // :app:checkDebugAarMetadata without this.
    //
    // compileSdk only decides which APIs the code may reference; it is
    // deliberately not accompanied by a targetSdk bump, which is what opts an
    // app in to new *runtime* behaviour and is a product decision rather than a
    // build fix. minSdk and targetSdk stay on Flutter's own pins below.
    //
    // AGP 9.1.0 warns that 36 is its highest tested compileSdk. That is a
    // warning, not a failure. Remove this pin once Flutter's own default
    // reaches 37, or once AGP is upgraded to a release that tests against it.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.foodonthego.foodonthego"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
