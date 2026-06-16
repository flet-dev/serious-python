import com.android.build.gradle.LibraryExtension
import de.undercouch.gradle.tasks.download.Download
import org.gradle.api.InvalidUserDataException
import java.io.File
import java.util.Properties
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

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

    // Keep the stdlib/sitepackages/extract zips stored (uncompressed) in the APK so
    // zipimport can read members without zlib.
    androidResources {
        noCompress.add("zip")
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

// ---- native split -----------------------------------------------------------
// Relocate CPython extension modules to jniLibs/<abi>/lib<mangled>.so (loaded by
// basename via the linker namespace), leaving a .soref marker (content = the lib
// name) at each module's path in the pure zip. Pure code ships in ABI-common
// stored zips; path-hungry packages from SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES
// are moved whole into extract.zip and excluded from sitepackages.zip.
val extractPackages: List<String> = (System.getenv("SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES") ?: "")
    .split(",").map { it.trim() }.filter { it.isNotEmpty() }
val primaryAbi = abis.first()                       // pure zips are ABI-common: build once
val assetsDir = file("src/main/assets")
val bootstrapPy = file("../python/_sp_bootstrap.py")

val extTag = Regex("""\.(cpython-[^/]+|abi3)\.so$""")   // tagged extension module
fun isExtModule(name: String) = extTag.containsMatchIn(name)
fun extDottedName(rel: String): String {               // slash-rel path -> dotted import name
    val dir = rel.substringBeforeLast('/', "")
    val mod = rel.substringAfterLast('/').replace(extTag, "")
    return (if (dir.isEmpty()) "" else dir.replace('/', '.') + ".") + mod
}
fun mangledLib(dotted: String) = "lib" + dotted.replace('.', '-') + ".so"
fun sorefPath(rel: String) = rel.replace(extTag, ".soref")
fun isAllowlisted(rel: String) = extractPackages.any { rel == it || rel.startsWith("$it/") }

// Minimal STORED (uncompressed) zip so members stay readable via zipimport.get_data
// with no zlib at runtime.
class StoredZip(val out: ZipOutputStream) {
    fun add(name: String, data: ByteArray) {
        val e = ZipEntry(name).apply {
            method = ZipEntry.STORED
            size = data.size.toLong()
            compressedSize = data.size.toLong()
            crc = CRC32().apply { update(data) }.value
        }
        out.putNextEntry(e); out.write(data); out.closeEntry()
    }
    fun close() = out.close()
}
fun storedZip(f: File): StoredZip {
    f.parentFile.mkdirs()
    return StoredZip(ZipOutputStream(f.outputStream()).apply { setMethod(ZipOutputStream.STORED) })
}

// Loop through abiFilters
val packageTasks = mutableListOf<String>()
for (abi in abis) {
    if (siteSrcDir == null || siteSrcDir.isBlank()) {
        throw InvalidUserDataException("SERIOUS_PYTHON_SITE_PACKAGES environment variable is not set.")
    }

    packageTasks.add("splitStdlib_$abi")
    packageTasks.add("splitSitePackages_$abi")
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

    val jniDir = file("src/main/jniLibs/$abi")
    val abiSiteDir = file("$siteSrcDir/$abi")
    val bundleFile = File(jniDir, "libpythonbundle.so")
    val isPrimary = abi == primaryAbi

    // Crack the stdlib bundle (libpythonbundle.so): modules/*.so -> mangled jniLibs
    // (+ .soref markers in stdlib.zip), stdlib/* -> stdlib.zip root, then delete it.
    tasks.register("splitStdlib_$abi") {
        dependsOn("untarFile_$abi")
        // The doLast rewrites jniLibs/<abi> (mangled libs in, bundle out); declare it as a
        // tracked output and always re-run so AGP's native-libs merge re-packages.
        outputs.dir(jniDir)
        outputs.dir(assetsDir)
        outputs.upToDateWhen { false }
        doLast {
            if (!bundleFile.exists()) throw GradleException("libpythonbundle.so missing in jniLibs/$abi")
            val zip = if (isPrimary) storedZip(File(assetsDir, "stdlib.zip")) else null
            ZipFile(bundleFile).use { zf ->
                val en = zf.entries()
                while (en.hasMoreElements()) {
                    val e = en.nextElement()
                    if (e.isDirectory) continue
                    val data = zf.getInputStream(e).readBytes()
                    val name = e.name
                    when {
                        name.startsWith("modules/") -> {
                            val rel = name.removePrefix("modules/")     // top-level module file
                            when {
                                isExtModule(rel) -> {
                                    val lib = mangledLib(extDottedName(rel))
                                    File(jniDir, lib).writeBytes(data)
                                    zip?.add(sorefPath(rel), lib.toByteArray())
                                }
                                rel.endsWith(".so") -> File(jniDir, File(rel).name).writeBytes(data)
                                else -> zip?.add(rel, data)
                            }
                        }
                        name.startsWith("stdlib/") -> zip?.add(name.removePrefix("stdlib/"), data)
                        else -> zip?.add(name, data)
                    }
                }
            }
            zip?.add("_sp_bootstrap.py", bootstrapPy.readBytes())   // finder at zip root
            // Interim install hook: site (during Py_Initialize) imports this and
            // installs the finder. Superseded by the dart-bridge pre-site shim (F).
            zip?.add("sitecustomize.py", "import _sp_bootstrap\n_sp_bootstrap.install()\n".toByteArray())
            zip?.close()
            bundleFile.delete()                                     // fake-zip must not ship
        }
    }

    // Site-packages tree: tagged .so -> mangled jniLibs (+ .soref markers), pure ->
    // sitepackages.zip (or extract.zip if allowlisted); opt/ is left to copyOpt.
    tasks.register("splitSitePackages_$abi") {
        dependsOn("untarFile_$abi")
        mustRunAfter("copyOpt_$abi", "splitStdlib_$abi")
        outputs.dir(jniDir)
        outputs.dir(assetsDir)
        outputs.upToDateWhen { false }
        doLast {
            jniDir.mkdirs()
            val siteZip = if (isPrimary) storedZip(File(assetsDir, "sitepackages.zip")) else null
            val extractZip = if (isPrimary) storedZip(File(assetsDir, "extract.zip")) else null
            abiSiteDir.walkTopDown().filter { it.isFile }.forEach { f ->
                val rel = f.relativeTo(abiSiteDir).path.replace(File.separatorChar, '/')
                if (rel == "opt" || rel.startsWith("opt/")) return@forEach        // dep libs -> copyOpt
                val zip = if (isAllowlisted(rel)) extractZip else siteZip
                when {
                    isExtModule(rel) -> {
                        val lib = mangledLib(extDottedName(rel))
                        f.copyTo(File(jniDir, lib), overwrite = true)
                        zip?.add(sorefPath(rel), lib.toByteArray())
                    }
                    rel.endsWith(".so") -> f.copyTo(File(jniDir, f.name), overwrite = true)  // untagged -> dep
                    else -> zip?.add(rel, f.readBytes())
                }
            }
            siteZip?.close()
            extractZip?.close()
        }
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
