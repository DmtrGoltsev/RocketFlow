plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val productionApiBaseUrl = "http://45.10.110.42/rocket-api"

fun resolveConfigValue(
    gradlePropertyName: String,
    envVariableName: String
): String? {
    val gradleOverride = project.findProperty(gradlePropertyName) as String?
    val envOverride = System.getenv(envVariableName)
    return gradleOverride?.takeIf { it.isNotBlank() }
        ?: envOverride?.takeIf { it.isNotBlank() }
}

fun resolveRocketFlowApiBaseUrl(buildTypeName: String): String {
    val capitalizedBuildTypeName = buildTypeName.replaceFirstChar { it.uppercaseChar() }
    return resolveConfigValue(
        "rocketflow${capitalizedBuildTypeName}ApiBaseUrl",
        "ROCKETFLOW_ANDROID_${buildTypeName.uppercase()}_API_BASE_URL"
    )
        ?: resolveConfigValue("rocketflowApiBaseUrl", "ROCKETFLOW_ANDROID_API_BASE_URL")
        ?: productionApiBaseUrl
}

fun usesCleartextTraffic(apiBaseUrl: String): Boolean {
    return apiBaseUrl.trim().startsWith("http://", ignoreCase = true)
}

fun isLocalOnlyApiBaseUrl(apiBaseUrl: String): Boolean {
    return listOf("10.0.2.2", "127.0.0.1", "localhost").any { localHost ->
        apiBaseUrl.contains(localHost, ignoreCase = true)
    }
}

fun buildConfigString(value: String): String {
    return "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""
}

fun resolveOptionalConfig(
    gradlePropertyName: String,
    envVariableName: String
): String {
    return resolveConfigValue(gradlePropertyName, envVariableName) ?: ""
}

android {
    namespace = "com.rocketflow.companion"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.rocketflow.companion"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_APPLICATION_ID",
            buildConfigString(resolveOptionalConfig("rocketflowFirebaseApplicationId", "ROCKETFLOW_ANDROID_FIREBASE_APPLICATION_ID"))
        )
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_API_KEY",
            buildConfigString(resolveOptionalConfig("rocketflowFirebaseApiKey", "ROCKETFLOW_ANDROID_FIREBASE_API_KEY"))
        )
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_PROJECT_ID",
            buildConfigString(resolveOptionalConfig("rocketflowFirebaseProjectId", "ROCKETFLOW_ANDROID_FIREBASE_PROJECT_ID"))
        )
        buildConfigField(
            "String",
            "ROCKETFLOW_FIREBASE_GCM_SENDER_ID",
            buildConfigString(resolveOptionalConfig("rocketflowFirebaseGcmSenderId", "ROCKETFLOW_ANDROID_FIREBASE_GCM_SENDER_ID"))
        )
    }

    buildTypes {
        debug {
            val debugApiBaseUrl = resolveRocketFlowApiBaseUrl("debug")
            buildConfigField("String", "ROCKETFLOW_API_BASE_URL", buildConfigString(debugApiBaseUrl))
            manifestPlaceholders["rocketflowUsesCleartextTraffic"] = usesCleartextTraffic(debugApiBaseUrl).toString()
        }

        release {
            val releaseApiBaseUrl = resolveRocketFlowApiBaseUrl("release")
            buildConfigField("String", "ROCKETFLOW_API_BASE_URL", buildConfigString(releaseApiBaseUrl))
            manifestPlaceholders["rocketflowUsesCleartextTraffic"] = usesCleartextTraffic(releaseApiBaseUrl).toString()
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

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") }) {
        val releaseApiBaseUrl = resolveRocketFlowApiBaseUrl("release")
        require(!isLocalOnlyApiBaseUrl(releaseApiBaseUrl)) {
            "Release builds must not use a local-only RocketFlow API base URL: $releaseApiBaseUrl. " +
                "Use rocketflowDebugApiBaseUrl or ROCKETFLOW_ANDROID_DEBUG_API_BASE_URL for emulator-only debug builds."
        }
    }
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

    testImplementation("junit:junit:4.13.2")
    testImplementation("androidx.test:core-ktx:1.6.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    testImplementation("org.json:json:20240303")
    testImplementation("org.robolectric:robolectric:4.12.2")
}
