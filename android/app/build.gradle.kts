import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名（33.16）。
//
// 以前 release 写死 `signingConfigs.getByName("debug")` —— 自用包能装，但换台机器
// 重打一次就签不上（debug key 每台机器不同），也永远不能上架。
//
// 现在：只要 `android/key.properties` 存在就用它签，不存在就退回 debug 签名。
//   * key.properties 与 keystore 都不进 git（.gitignore 已列），口令不入库；
//   * 退回 debug 时会在构建日志里打一行 lifecycle 提示，不会静默；
//   * 建 key.properties 的步骤见 docs/BUILD.md「七、正式签名」。
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
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

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // 用 rootProject.file 而不是 file：相对路径按 `android/` 解析，
                // 与 key.properties 自己的位置一致（`file` 会按 android/app/ 解析，
                // 2026-11-20 踩过：jks 放在 android/ 下会报 Missing keystore）。
                storeFile = keystoreProperties["storeFile"]?.let { rootProject.file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
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
            // 有 key.properties 就用正式签名，没有就退回 debug（自用包照常能打）。
            // 别把这里改回写死 debug：那样换台机器重打就签不上同一个包。
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.lifecycle(
                    "==> 没找到 android/key.properties，release 退回 debug 签名（33.16）。" +
                        "建法见 docs/BUILD.md「七、正式签名」。",
                )
                signingConfigs.getByName("debug")
            }
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbiFilters)
            }
            // Flutter 的 release 默认开 R8（shrink），而 ONNX Runtime 的 Java
            // 层是 native 反查类的，被裁掉就在 JNI 里 abort。keep 规则见
            // android/app/proguard-rules.pro 顶部的说明（2026-11-15 踩过）。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
