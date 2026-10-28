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
//
// 但这条「能跑」的便利只该给**本地联调**。真打 release 包时静默退回 debug 签名会产出
// 一个「看起来是正式包、老用户却装不上」的 APK —— 签名不同必须卸载重装，账目全没。
// 所以 assembleRelease 挂了守卫（见文件末尾），配置阶段仍然不抛：
// `flutter build apk --release --config-only` 与 `:app:processReleaseManifest`
// 是 CI 的 release-permissions job 的必经之路，它在没有密钥的环境下跑，不能被拦。
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

// ---------------------------------------------------------------------------
// release 缺密钥即失败。
//
// 上面 `signingConfig` 的回落逻辑是给**本地联调**用的逃生阀，不是给发版用的。
// 没有这层守卫时，缺 key.properties 的机器照样能编出一个签成 debug 的「release」
// 包：它自己装得上，已经装了正式签名的老用户却装不上（签名不同必须卸载，
// 卸载就把账目一起删了）。构建成功但产物是废的，比构建失败危险得多。
//
// 两个必须守住的边界：
// 1) **只在执行期抛**。CI 的 release-permissions job 走
//    `flutter build apk --release --config-only` + `:app:processReleaseManifest`
//    来验证「发布包里没有 INTERNET 权限」，这两步不产出 APK、也没有密钥 ——
//    若在配置阶段抛，那条门禁就再也跑不起来了。
// 2) **保留签名回落**。逃生阀生效时还得有 debug 签名可签，否则守卫一放开就撞上
//    「signingConfig 为空」。
// ---------------------------------------------------------------------------
// 在配置阶段就把这两个值取出来存成局部量：doFirst 里再去读 project 会破坏
// Gradle 的配置缓存（以后一旦开启就会报错）。
val allowDebugSigning = (project.findProperty("allowDebugSigning") as String?) == "true"

tasks.matching { it.name == "assembleRelease" }.configureEach {
    doFirst {
        if (!hasReleaseKey && !allowDebugSigning) {
            throw GradleException(
                """
                |
                |这是一次 **release** 构建，但 android/key.properties 不存在。
                |缺它的后果不是"构建失败"，而是**悄悄签成 debug 签名**：包能编出来、
                |也能装在这台机器上，但装了正式签名版本的手机会因为签名不同而装不上，
                |必须先卸载 —— 卸载会把本机账目一起删掉。
                |
                |要发版：把 key.properties 与 release.jks 放好（格式见 .gitignore 里的条目）。
                |只是本地联调 / 出并存测试包：加 -PallowDebugSigning=true 显式放行，例如
                |  flutter build apk --release -PallowDebugSigning=true
                |（配合 -PappIdSuffix=.dev 可与手机上已有的正式版共存。）
                |
                """.trimMargin(),
            )
        }
    }
}
