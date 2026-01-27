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

android {
    namespace = "com.example.three_sec_vlog"
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
        applicationId = "com.example.three_sec_vlog"
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
            
            // 코드 최적화 설정 (필요 시 true로 변경 가능)
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}