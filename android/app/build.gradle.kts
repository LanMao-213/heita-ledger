import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名。`key.properties` 与 `*.jks` **永不进仓库**（见 .gitignore）；
// 新克隆的机器上没有这两个文件，正式签名配置就不注册，release 自动退回 debug 签名，
// 保证「能拉下来就能跑」，不会因为缺密钥直接构建失败。
//
// 密钥路径与口令只从以下两处来（阶段 6 的 tools/build_release.sh）：
//   ① `android/key.properties`（本机手工放置，不入库）
//   ② 环境变量 HEITA_STORE_FILE / HEITA_STORE_PASSWORD / HEITA_KEY_ALIAS / HEITA_KEY_PASSWORD
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists() ||
    System.getenv("HEITA_STORE_FILE") != null
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
fun signingValue(envKey: String, propKey: String): String? =
    System.getenv(envKey) ?: keystoreProperties.getProperty(propKey)

android {
    // 包名固定为 com.heita.ledger：与旧版同包名，才能覆盖安装并直读旧库。
    // 单一包名，没有任何 suffix 分支（原版 -PappIdSuffix 的双包机制已废弃）。
    namespace = "com.heita.ledger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.heita.ledger"
        // minSdk 24（Android 7.0）＝ SQLite 3.9.2，部分唯一索引 / 表达式索引都支持。
        // 显式写死而不是用 flutter.minSdkVersion，避免 Flutter 升级时被动漂移。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = signingValue("HEITA_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("HEITA_KEY_PASSWORD", "keyPassword")
                storeFile = signingValue("HEITA_STORE_FILE", "storeFile")?.let { file(it) }
                storePassword = signingValue("HEITA_STORE_PASSWORD", "storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // 没有密钥（别人的机器 / CI）退回 debug 签名，保证构建能过
                signingConfigs.getByName("debug")
            }
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
