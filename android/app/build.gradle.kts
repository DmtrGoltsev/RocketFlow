plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

fun resolveRocketFlowApiBaseUrl(): String {
    val gradleOverride = project.findProperty("rocketflowApiBaseUrl") as String?
    val envOverride = System.getenv("ROCKETFLOW_ANDROID_API_BASE_URL")
    return gradleOverride?.takeIf { it.isNotBlank() }
        ?: envOverride?.takeIf { it.isNotBlank() }
        ?: "http://10.0.2.2:8080/api"
}

fun usesCleartextTraffic(apiBaseUrl: String): Boolean {
    return apiBaseUrl.trim().startsWith("http://", ignoreCase = true)
}

fun resolveOptionalConfig(
    gradlePropertyName: String,
    envVariableName: String
): String {
    val gradleOverride = project.findProperty(gradlePropertyName) as String?
    val envOverride = System.getenv(envVariableName)
    return gradleOverride?.takeIf { it.isNotBlank() }
        ?: envOverride?.takeIf { it.isNotBlank() }
        ?: ""
}

android {
    namespace = "com.rocketflow.companion"
    compileSdk = 34
    val apiBaseUrl = resolveRocketFlowApiBaseUrl()

    defaultConfig {
        applicationId = "com.rocketflow.companion"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "ROCKETFLOW_API_BASE_URL", "\"$apiBaseUrl\"")
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_APPLICATION_ID",
            "\"${resolveOptionalConfig("rocketflowFirebaseApplicationId", "ROCKETFLOW_ANDROID_FIREBASE_APPLICATION_ID")}\""
        )
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_API_KEY",
            "\"${resolveOptionalConfig("rocketflowFirebaseApiKey", "ROCKETFLOW_ANDROID_FIREBASE_API_KEY")}\""
        )
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_PROJECT_ID",
            "\"${resolveOptionalConfig("rocketflowFirebaseProjectId", "ROCKETFLOW_ANDROID_FIREBASE_PROJECT_ID")}\""
        )
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_GCM_SENDER_ID",
            "\"${resolveOptionalConfig("rocketflowFirebaseGcmSenderId", "ROCKETFLOW_ANDROID_FIREBASE_GCM_SENDER_ID")}\""
        )
        manifestPlaceholders["rocketflowUsesCleartextTraffic"] = usesCleartextTraffic(apiBaseUrl).toString()
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        buildConfig = true
    }
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-ktx:1.9.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("com.google.firebase:firebase-messaging:24.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    androidTestImplementation("androidx.test:core-ktx:1.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}
