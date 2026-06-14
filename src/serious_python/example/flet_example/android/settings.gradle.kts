pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // KGP 2.3.21 required: Flet's transitive screen_brightness_android ships a
    // Kotlin 2.3.x stdlib whose metadata can't be read by KGP < 2.3 (the 3.44.2
    // template default is 2.2.20).
    id("org.jetbrains.kotlin.android") version "2.3.21" apply false
}

include(":app")
