plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.terra"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
        targetSdk = 34

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Architectures that Zig cross-compiles for Android
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("kotlin/dev/terra")

            // JNI native libraries built via Zig cross-compilation:
            //   zig build -Dtarget=aarch64-linux-android → jniLibs/arm64-v8a/libterra.so
            //   zig build -Dtarget=x86_64-linux-android  → jniLibs/x86_64/libterra.so
            jniLibs.srcDirs("jniLibs")
        }

        getByName("test") {
            java.srcDirs("test")
        }

        getByName("androidTest") {
            java.srcDirs("androidTest")
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test:runner:1.5.2")
}
