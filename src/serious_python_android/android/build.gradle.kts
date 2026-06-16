import com.android.build.gradle.LibraryExtension
import de.undercouch.gradle.tasks.download.Download
import org.gradle.api.InvalidUserDataException
import java.io.File
import java.util.Properties

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // The Android Gradle Plugin knows how to build native code with the NDK.
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("de.undercouch:gradle-download-task:5.6.0")
    }
}

group = "com.flet.serious_python_android"
version = "3.0.0"

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply(plugin = "com.android.library")
apply(plugin = "de.undercouch.download")

// Python runtime versions come from the generated python_versions.properties
// (a snapshot of python-build's manifest.json — see serious_python's
// `gen_version_tables`). SERIOUS_PYTHON_VERSION selects the version; everything
// else derives from the table. The per-field env vars are escape hatches.
val pv = Properties().apply {
    file("python_versions.properties").inputStream().use { load(it) }
}
val pythonVersion: String = System.getenv("SERIOUS_PYTHON_VERSION") ?: pv.getProperty("default_python_version")
val pythonFullVersion: String? = System.getenv("SERIOUS_PYTHON_FULL_VERSION") ?: pv.getProperty("$pythonVersion.full_version")
val pythonBuildDate: String = System.getenv("SERIOUS_PYTHON_BUILD_DATE") ?: pv.getProperty("python_build_release_date")
val dartBridgeVersion: String = System.getenv("DART_BRIDGE_VERSION") ?: pv.getProperty("dart_bridge_version")
if (pythonFullVersion == null) {
    val known = pv.keys.map { it.toString() }.filter { it.endsWith(".full_version") }.map { it.removeSuffix(".full_version") }
    throw GradleException("serious_python: unknown SERIOUS_PYTHON_VERSION '$pythonVersion'. Supported: ${known.joinToString(", ")}")
}

// python-build dropped 32-bit Android in 3.13 (PEP 738), so the
// python-android-dart-<ver>-armeabi-v7a tarball only exists for 3.12.
val abis: List<String> = if (pythonVersion == "3.12")
    listOf("arm64-v8a", "armeabi-v7a", "x86_64")
else
    listOf("arm64-v8a", "x86_64")

configure<LibraryExtension> {
    namespace = "com.flet.serious_python_android"

    // Bumping the plugin compileSdk requires all clients of this plugin to bump too.
    compileSdk = 36

    // No native code is compiled here — libdart_bridge.so is downloaded as a
    // pre-built artifact from flet-dev/dart-bridge releases (see the
    // downloadDartBridge_$abi tasks below) and dropped into jniLibs.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 21
        ndk {
            abiFilters.addAll(abis)
        }
    }

    packaging {
        jniLibs {
            keepDebugSymbols += setOf(
                "*/arm64-v8a/libpython*.so",
                "*/armeabi-v7a/libpython*.so",
                "*/x86/libpython*.so",
                "*/x86_64/libpython*.so",
            )
        }
    }
}

val fletCacheRoot: String? = System.getenv("FLET_CACHE_DIR")
val cacheBase: File = if (fletCacheRoot != null) File(fletCacheRoot) else File(System.getProperty("user.home"), ".flet/cache")
val pythonCacheDir = File(cacheBase, "python-build/v$pythonFullVersion")
val dartBridgeCacheDir = File(cacheBase, "dart-bridge/v$dartBridgeVersion")

tasks.register<Copy>("copyBuildDist") {
    val srcDir = System.getenv("SERIOUS_PYTHON_BUILD_DIST")
    if (srcDir != null) {
        from(srcDir)
        into("src/main/jniLibs")
    }
}

val siteSrcDir: String? = System.getenv("SERIOUS_PYTHON_SITE_PACKAGES")

// Loop through abiFilters
val packageTasks = mutableListOf<String>()
for (abi in abis) {
    if (siteSrcDir == null || siteSrcDir.isBlank()) {
        throw InvalidUserDataException("SERIOUS_PYTHON_SITE_PACKAGES environment variable is not set.")
    }

    packageTasks.add("zipSitePackages_$abi")
    packageTasks.add("copyOpt_$abi")

    tasks.register<Delete>("jniCleanUp_$abi") {
        delete("src/main/jniLibs/$abi")
    }

    val distFile = File(pythonCacheDir, "python-android-dart-$pythonFullVersion-$abi.tar.gz")
    tasks.register<Download>("downloadDistArchive_$abi") {
        src("https://github.com/flet-dev/python-build/releases/download/$pythonBuildDate/python-android-dart-$pythonFullVersion-$abi.tar.gz")
        dest(distFile)
        onlyIfModified(true)
        useETag("all")
        tempAndMove(true)
        doFirst { distFile.parentFile.mkdirs() }
    }
    tasks.register<Copy>("untarFile_$abi") {
        from(tarTree(distFile))
        into("src/main/jniLibs/$abi")
        dependsOn("jniCleanUp_$abi", "downloadDistArchive_$abi")
    }

    tasks.register<Copy>("copyOpt_$abi") {
        from(fileTree("$siteSrcDir/$abi/opt") { include("**/*.so") })
        into("src/main/jniLibs/$abi")
        eachFile { path = name }
        includeEmptyDirs = false
        dependsOn("jniCleanUp_$abi")
    }

    tasks.register<Zip>("zipSitePackages_$abi") {
        from(fileTree("$siteSrcDir/$abi"))
        archiveFileName.set("libpythonsitepackages.so")
        destinationDirectory.set(file("src/main/jniLibs/$abi"))
        dependsOn("jniCleanUp_$abi", "untarFile_$abi")
    }

    // dart-bridge ships a per-(abi × Python-minor-version) prebuilt .so. The
    // binary's DT_NEEDED is libpython3.X.so (version-specific), so the bridge
    // .so MUST match the libpython bundled in the same APK. We download from
    // the pinned dart_bridge_version release into a cache shared across
    // builds, then drop it as `libdart_bridge.so` (no version suffix) so the
    // Dart side can DynamicLibrary.open by a stable short name.
    val bridgeFile = File(dartBridgeCacheDir, "libdart_bridge-android-$abi-py$pythonVersion.so")
    tasks.register<Download>("downloadDartBridge_$abi") {
        src("https://github.com/flet-dev/dart-bridge/releases/download/v$dartBridgeVersion/libdart_bridge-android-$abi-py$pythonVersion.so")
        dest(bridgeFile)
        onlyIfModified(true)
        useETag("all")
        tempAndMove(true)
        doFirst { bridgeFile.parentFile.mkdirs() }
    }
    tasks.register<Copy>("copyDartBridge_$abi") {
        from(bridgeFile)
        into("src/main/jniLibs/$abi")
        rename(".*", "libdart_bridge.so")
        dependsOn("downloadDartBridge_$abi", "jniCleanUp_$abi")
    }
    packageTasks.add("copyDartBridge_$abi")
}

val copyOrUntar = tasks.register("copyOrUntar") {
    if (System.getenv("SERIOUS_PYTHON_BUILD_DIST") != null) {
        dependsOn("copyBuildDist")
    } else {
        dependsOn(packageTasks)
    }
}

tasks.named("preBuild") {
    dependsOn(copyOrUntar)
}
