import java.nio.file.Files
import java.nio.file.StandardCopyOption

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "dev.velox.agentcanvas"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.velox.agentcanvas"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")

    implementation("androidx.datastore:datastore-preferences:1.1.1")

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
}

val schemaFixtures = rootProject.projectDir.resolve("../../schema/fixtures")
val assetFixtures = layout.projectDirectory.dir("src/main/assets/fixtures").asFile
val fixtureNames = listOf(
    "empty.json",
    "sample-metrics.json",
    "demo-sm-one.json",
    "demo-md-one.json",
    "demo-md-two.json",
    "demo-lg-one.json",
    "demo-lg-two.json",
    "demo-xl-one.json",
    "expressiveness.json",
    "actions.json",
    "cover.json",
)

val syncSchemaFixtures by tasks.registering {
    group = "verification"
    description = "Copy schema/fixtures JSON into app assets without rewriting contents."
    inputs.files(fixtureNames.map { schemaFixtures.resolve(it) }).skipWhenEmpty()
    outputs.dir(assetFixtures)
    doLast {
        if (!schemaFixtures.isDirectory) {
            logger.lifecycle("schema/fixtures not found; keeping committed assets")
            return@doLast
        }
        assetFixtures.mkdirs()
        fixtureNames.forEach { name ->
            val source = schemaFixtures.resolve(name)
            if (source.isFile) {
                Files.copy(source.toPath(), assetFixtures.resolve(name).toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
        }
    }
}

tasks.named("preBuild") {
    dependsOn(syncSchemaFixtures)
}
