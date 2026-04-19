import java.util.Properties
import java.io.FileInputStream

// 1. 보안 키 설정 로드
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle 플러그인은 안드로이드 및 코틀린 플러그인 다음에 적용되어야 합니다.
    id("dev.flutter.flutter-gradle-plugin")
}

val googleServicesFile = file("google-services.json")
if (!googleServicesFile.exists()) {
    println("[FirebaseConfig] android/app/google-services.json is missing. Firebase 앱 초기화가 기본 옵션으로 실패할 수 있습니다.")
}

android {
    namespace = "com.dk.three_sec"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // 2. 서명 구성 (Release 모드용)
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "com.dk.three_sec"
        minSdk = 24  // FFmpeg Kit 사용을 위한 최소 사양
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64"))
        }
    }

    buildTypes {
        getByName("release") {
            // 3. 디버그 키 대신 생성한 릴리즈 키를 연결합니다.
            signingConfig = signingConfigs.getByName("release")
            
            // 코드 난독화/최적화 + 리소스 축소 활성화
            // mapping.txt는 build/app/outputs/mapping/release/mapping.txt 에 생성됩니다.
            isMinifyEnabled = true
            isShrinkResources = true

            // R8/Proguard 규칙
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.media3:media3-transformer:1.2.1")
    implementation("androidx.media3:media3-effect:1.2.1")
    implementation("androidx.media3:media3-common:1.2.1")
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))
}

apply(plugin = "com.google.gms.google-services")
