plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发版目标 ABI：由构建命令 -PtargetAbi=... 传入，配合 flutter --target-platform。
//   发版（自己的手机）→ -PtargetAbi=arm64 → 纯 arm64-v8a
//   模拟器冒烟（x86_64）→ -PtargetAbi=x64  → 纯 x86_64
// 缺省 arm64。为什么必须用 abiFilters 锁死：见 docs/BUILD.md。
// 口径与 I:\Examples\patrol_helper 的 android/app/build.gradle.kts 一致。
val targetAbi = (project.findProperty("targetAbi") as String?) ?: "arm64"
val targetAbiFilters = when (targetAbi) {
    "x64" -> listOf("x86_64")
    else -> listOf("arm64-v8a")
}

android {
    namespace = "com.dlaoshi.dlaoshi_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dlaoshi.dlaoshi_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 只打一个 ABI。
            //
            // 为什么需要：`flutter build apk --target-platform android-arm64`
            // 只裁 Flutter 自己的产物，带预编译 .so 的插件（onnxruntime /
            // neural_tts / flutter_onnxruntime）仍然把三套一起塞进来 ——
            // 138MB 里有 52MB 是根本用不上的两份，而且那两份目录里
            // 只有第三方 so、没有 libapp.so / libflutter.so，是残缺的。
            // 另外还得在 gradle.properties 里 disable-abi-filtering=true，
            // 否则 Flutter 插件会覆盖这里的 abiFilters。
            signingConfig = signingConfigs.getByName("debug")
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbiFilters)
            }
        }
    }

    // release 用传统 jniLibs 打包方式，配合 useLegacyPackaging 让首启动不必解压 so
    packaging {
        jniLibs {
            useLegacyPackaging = true
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
