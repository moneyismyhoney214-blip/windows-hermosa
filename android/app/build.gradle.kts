import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Exclude the outdated `local.libs:centrum-printer:1.0.0_20221223`
// jar that NearPay's `kernelsdk-release` pulls in transitively. It
// ships an older snapshot of the Centerm `com.pos.sdk.*` AIDL stubs
// (different transaction codes than the 2025 service installed on
// the Q7), and roughly 87 of its classes collide with our local
// CpaySDKLib_Q jar — so leaving it on the classpath either fails the
// merge step (R8) or, worse, wins the duplicate-class fight at dex
// time and silently misroutes every IPC call to the Q7 printer
// service. NearPay's payment flow on the Q7 doesn't print through
// that jar (the host app does), so the exclusion is safe.
configurations.all {
    exclude(group = "local.libs", module = "centrum-printer")
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
        // Bumped 34 → 35: Play Console now blocks uploads targeting < 35.
        // The 16KB-page warning may persist for prebuilt vendor .so files
        // (NearPay 0.0.187 / Sunmi CpaySDK / mobile_scanner) that aren't
        // re-aligned yet, but AGP 8.11+ auto-aligns everything it can
        // re-pack at packaging time. Misaligned libs that remain after a
        // build are listed in the Play Console "Native libraries" report.
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ABI splitting is controlled from Flutter build flags.
    }

    dependencies {
        // NearPay Terminal SDK. The outdated transitive
        // `local.libs:centrum-printer` jar is removed at the
        // configuration level (above) so the classpath stays clean
        // across every variant.
        implementation("io.nearpay:terminalsdk-release:0.0.187")
        implementation("com.google.android.gms:play-services-location:20.0.0")
        // Huawei HMS Location intentionally dropped: the only consumer
        // (NearpayProvider's huaweiSafetyDetectApiKey builder call) is
        // already conditionalized and the cashier passes an empty key,
        // so the native libTransform.so from com.huawei.hms:core was
        // dead weight. It was also the only 4KB-aligned .so coming
        // from a removable Gradle dep — pulling it out drops one of
        // the Play Console 16KB-page warnings without breaking anything.
        // Centerm Q7 POS SDK (printer + system services). Backed by the
        // com.pos.smartposservice APK that must be pre-installed on Q7
        // hardware. Detected at runtime — code paths are no-ops on
        // non-Q7 devices.
        implementation(fileTree("libs") { include("*.jar") })
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
            // Drop Telpo POS hardware bindings (USB + serial helpers).
            // NearPay's cardreader-release pulls local.libs:telpo-lib in
            // as one of ~15 vendor support libs, but the cashier runs on
            // Sunmi/Centerm/Q7 hardware in SoftPOS (NFC) mode and never
            // touches Telpo devices. The two .so files were also the
            // last 4KB-aligned arm64 libs failing Play Console's 16KB
            // page check after the Huawei HMS drop, so excluding them
            // closes the warning. Re-add ONLY if the app starts
            // supporting Telpo terminals.
            excludes += setOf(
                "**/libserial-util.so",
                "**/libusb-util.so",
            )
        }
    }
}

flutter {
    source = "../.."
}
