plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

apply(plugin = "com.google.gms.google-services")

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

android {
    namespace = "com.marc.new_test_store"
    compileSdk = 35
    ndkVersion = "25.1.8937393"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.marc.new_test_store"
        minSdk = 23  // Increased from 21 to fix network capability issues
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Add this to fix Firebase messaging issues
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    implementation(platform("com.google.firebase:firebase-bom:33.15.0"))
    // TODO: Add the dependencies for Firebase products you want to use
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
}