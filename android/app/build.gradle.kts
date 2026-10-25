import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名。key.properties 与 release.jks 都不进仓库（见 .gitignore）；
// 新克隆的机器上没有这两个文件，正式签名配置就不注册，release 自动退回 debug 签名，
// 保证「能拉下来就能跑」，不会因为缺密钥直接构建失败。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.heita.ledger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        //
        // 后缀用于打出**并排安装的测试包**：`-PappIdSuffix=.dev` 会得到
        // com.heita.ledger.dev。真机走查时手机上通常已经装了旧版，而旧版是
        // debug 签名、装不上正式签名的包（签名不同必须卸载）。加个后缀就能
        // 两个包共存，旧版账目一条不动。不传这个参数时和原来完全一致。
        applicationId = "com.heita.ledger" + ((project.findProperty("appIdSuffix") as String?) ?: "")
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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                // 有正式密钥就用它：换电脑重新打包也能覆盖安装，本地账目不会因为
                // 签名不同而被迫卸载清空
                signingConfigs.getByName("release")
            } else {
                // 没有密钥（别人的机器 / CI）退回 debug 签名，保证构建能过
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            // 只保留 arm64-v8a。
            //
            // 为什么需要这条：Flutter 的插件（这里是 dartjni）自带全 ABI 的 .so，
            // 即使 `--target-platform android-arm64` 也会被一起打进来，于是包里同时
            // 出现 lib/armeabi-v7a/libdartjni.so —— 看起来支持 32 位，实际上
            // libapp.so 只有 arm64。32 位设备会**装得上然后一启动就闪退**。
            //
            // 排除掉之后，32 位设备在安装阶段就被
            // INSTALL_FAILED_NO_MATCHING_ABIS 拒掉，原因清楚，也不会留下一个
            // 「装了但打不开」的坏印象。
            //
            // 不用 `--split-per-abi`：那个会给 versionCode 加 1000*ABI 偏移
            // （23 变成 2023），之后正常打包的版本号反而比它小，升级直接卡死。
            // `tools/verify_apk.py` 的版本号校验就是被这个坑触发的。
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
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
