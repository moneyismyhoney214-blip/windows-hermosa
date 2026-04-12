import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// NEARPAY MAVEN REPOSITORY
repositories {
    google()
    mavenCentral()

    val nearpayToken = providers.gradleProperty("nearpayPosGitlabReadToken")
        .orElse(providers.environmentVariable("NEARPAY_POS_GITLAB_READ_TOKEN"))
        .orNull

    if (nearpayToken != null && !nearpayToken.trim().isEmpty()) {
        maven {
            url = uri("https://gitlab.com/api/v4/projects/37026421/packages/maven")
            credentials(HttpHeaderCredentials::class) {
                name = "Private-Token"
                value = nearpayToken.trim()
            }
            authentication {
                create<HttpHeaderAuthentication>("header")
            }
        }
    }

    maven { url = uri("https://developer.huawei.com/repo/") }
    maven { url = uri("https://jitpack.io") }
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "p.cash.hermosaapp.com"
    // Required by plugins compiled against newer SDKs.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "p.cash.hermosaapp.com"
        // NearPay requires minSdk 28
        minSdk = 28
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ABI splitting is controlled from Flutter build flags.
    }

    dependencies {
        // NearPay Terminal SDK
        implementation("io.nearpay:terminalsdk-release:0.0.169")
        implementation("com.google.android.gms:play-services-location:20.0.0")
        implementation("com.huawei.hms:location:6.4.0.300")
    }

    signingConfigs {
        create("release") {
            // أولوية لمتغيرات البيئة (Codemagic)
            val cmKeystorePath = System.getenv("CM_KEYSTORE_PATH")
            val cmKeystorePassword = System.getenv("CM_KEYSTORE_PASSWORD")
            val cmKeyAlias = System.getenv("CM_KEY_ALIAS")
            val cmKeyPassword = System.getenv("CM_KEY_PASSWORD")

            if (!cmKeystorePath.isNullOrBlank()) {
                // Codemagic mode
                storeFile = file(cmKeystorePath)
                storePassword = cmKeystorePassword
                keyAlias = cmKeyAlias
                keyPassword = cmKeyPassword
            } else {
                // Local mode - from key.properties
                val storeFilePath = keystoreProperties["storeFile"] as String?
                if (!storeFilePath.isNullOrBlank()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // التحقق من وجود إعدادات التوقيع
            val hasLocalConfig = keystorePropertiesFile.exists()
            val hasCodemagicConfig = !System.getenv("CM_KEYSTORE_PATH").isNullOrBlank()

            if (hasLocalConfig || hasCodemagicConfig) {
                // يوجد إعدادات توقيع - استخدمها
                signingConfig = signingConfigs.getByName("release")
            } else {
                // ⚠️ تحذير: بناء بدون توقيع (للتستنج فقط)
                println("⚠️ WARNING: Building release without signing. Add credentials for production builds.")
                signingConfig = signingConfigs.getByName("debug")  // استخدم debug signing (unsigned)
            }

            // ✅ تفعيل ضغط الكود والموارد
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // NearPay native libs fail llvm-strip; keep symbols only for those libs.
    packaging {
        jniLibs {
            keepDebugSymbols.add("**/libspin*.so")
        }
    }
}

flutter {
    source = "../.."
}
