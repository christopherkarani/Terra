plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.terra"
    compileSdk = 34

    defaultConfig {
        minSdk = 26

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

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("kotlin/dev/terra")

            // Native artifacts are produced by Scripts/build-libtera-android.sh:
            //   Zig builds libterra.a per ABI
            //   ndk-build links terra_jni.c + libterra.a into jniLibs/<abi>/libtera.so
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

val requiredNativeAbis = listOf("arm64-v8a", "x86_64")

tasks.register("verifyNativeLibs") {
    group = "verification"
    description = "Verifies release packaging has Terra JNI libraries for all supported ABIs."

    doLast {
        val missing = requiredNativeAbis
            .map { abi -> file("jniLibs/$abi/libtera.so") }
            .filterNot { it.isFile }

        if (missing.isNotEmpty()) {
            throw GradleException(
                "Missing native Terra JNI libraries: " +
                    missing.joinToString { it.relativeTo(projectDir).path } +
                    ". Run `bash ../Scripts/build-libtera-android.sh` before release assembly."
            )
        }
    }
}

tasks.matching {
    it.name == "preReleaseBuild" || it.name == "assembleRelease" || it.name == "bundleRelease"
}.configureEach {
    dependsOn("verifyNativeLibs")
}
