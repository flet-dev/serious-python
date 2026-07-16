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
version = "4.3.3"

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

// ABIs come from python-build's manifest (the per-minor `android_abis` array,
// flattened into python_versions.properties by `gen_version_tables`). A future
// minor only needs the manifest edit — no Gradle change here.
val abis: List<String> = (pv.getProperty("$pythonVersion.android_abis")
    ?: throw GradleException(
        "serious_python: python_versions.properties has no '$pythonVersion.android_abis'"))
    .split(",").map { it.trim() }.filter { it.isNotEmpty() }

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
        // Keep rules for classes pyjnius / the native runtime resolve by name at
        // runtime (e.g. PythonActivity.mActivity); merged into the consuming app's
        // R8 pass so release builds don't obfuscate/strip them.
        consumerProguardFiles("consumer-rules.pro")
    }

    // No jniLibs packaging config needed: the native modules are real ELF .so that
    // land in the consuming app's jniLibs (relocated by the split tasks) and are
    // loaded memory-mapped from the APK — modern packaging (minSdk 23+) is all that
    // is required. (The old keepDebugSymbols rules were only needed for the previous
    // fake-.so-zip scheme.)

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
//
// Each entry matches either an exact path or anything under it (`flask` ->
// flask/...). An entry containing a `*` or `?` wildcard is a glob matched
// against the top-level path component, so `flask*` also catches the sibling
// `flask-<version>.dist-info/` (and any `flask_*` package).
val extractPackages: List<String> = (System.getenv("SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES") ?: "")
    .split(",").map { it.trim() }.filter { it.isNotEmpty() }
fun globToRegex(glob: String): Regex =
    Regex(glob.map { c ->
        when (c) {
            '*' -> ".*"
            '?' -> "."
            else -> Regex.escape(c.toString())
        }
    }.joinToString(""))
val extractGlobs: List<Regex> =
    extractPackages.filter { '*' in it || '?' in it }.map(::globToRegex)
val extractPlain: List<String> =
    extractPackages.filter { '*' !in it && '?' !in it }
// Pure zips are ABI-common: build once, from the first ABI whose site-packages
// tree was actually staged — `flet build --arch` may stage a subset of the ABIs
// (e.g. only x86_64), and a hardcoded abis.first() would then walk a missing
// dir and silently ship an EMPTY sitepackages.zip. No staged dir at all is
// legitimate (packaged with no requirements): fall back to abis.first(), whose
// empty walk correctly yields empty zips.
val primaryAbi = abis.firstOrNull { siteSrcDir != null && File(siteSrcDir, it).isDirectory }
    ?: abis.first().also {
        logger.lifecycle(
            "serious_python: no staged site-packages under $siteSrcDir; " +
            "sitepackages.zip will be empty")
    }
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
fun isAllowlisted(rel: String): Boolean =
    extractPlain.any { rel == it || rel.startsWith("$it/") } ||
    (extractGlobs.isNotEmpty() && extractGlobs.any { it.matches(rel.substringBefore('/')) })

// Minimal STORED (uncompressed) zip so members stay readable via zipimport.get_data
// with no zlib at runtime.
class StoredZip(val out: ZipOutputStream) {
    private val names = mutableSetOf<String>()
    fun add(name: String, data: ByteArray) {
        val e = ZipEntry(name).apply {
            method = ZipEntry.STORED
            size = data.size.toLong()
            compressedSize = data.size.toLong()
            crc = CRC32().apply { update(data) }.value
        }
        out.putNextEntry(e); out.write(data); out.closeEntry()
        names.add(name)
    }
    // zipimport cannot import PEP 420 namespace packages — package directories
    // with no __init__.py (e.g. flask's `flask/sansio/`). On a real filesystem
    // the path finder imports them implicitly, but inside a stored zip served by
    // zipimport they're invisible. Inject an empty __init__.py into every package
    // dir that has importable content (a .py/.pyc/.soref module) but no __init__,
    // turning namespace packages into regular ones zipimport can resolve. Call
    // before close(). (Not needed for extract.zip — that's unpacked to disk.)
    fun synthesizePackageInits() {
        val moduleExts = listOf(".py", ".pyc", ".soref")
        val pkgDirs = sortedSetOf<String>()
        for (n in names) {
            if (moduleExts.none { n.endsWith(it) }) continue
            if (n.split('/').any { it == "__pycache__" }) continue
            var dir = n.substringBeforeLast('/', "")
            while (dir.isNotEmpty()) {
                pkgDirs.add(dir)
                dir = dir.substringBeforeLast('/', "")
            }
        }
        for (d in pkgDirs) {
            if ("$d/__init__.py" in names || "$d/__init__.pyc" in names) continue
            add("$d/__init__.py", ByteArray(0))
        }
    }
    fun close() = out.close()
}
fun storedZip(f: File): StoredZip {
    f.parentFile.mkdirs()
    return StoredZip(ZipOutputStream(f.outputStream()).apply { setMethod(ZipOutputStream.STORED) })
}

// Loop through abiFilters
val packageTasks = mutableListOf<String>()

// Remove jniLibs/<abi> dirs for ABIs not in the current set (e.g. stale armeabi-v7a
// 3.12 leftovers when building 3.14) so they aren't packaged into the APK/AAB.
val jniLibsRoot = file("src/main/jniLibs")
tasks.register("cleanStaleAbis") {
    doLast {
        jniLibsRoot.listFiles()?.forEach { d ->
            if (d.isDirectory && d.name !in abis) d.deleteRecursively()
        }
    }
}
packageTasks.add("cleanStaleAbis")

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
        // The ABI-common stdlib.zip is built once (from the primary ABI) but must
        // also carry every OTHER ABI's arch-specific `_sysconfigdata__<arch>` (see
        // the harvest in doLast). Make the primary task depend on the other ABIs'
        // untar so their bundles exist to read, and hold non-primary tasks until
        // the primary has read them (each task deletes its own bundle at the end).
        if (isPrimary) {
            abis.forEach { other -> if (other != abi) dependsOn("untarFile_$other") }
        } else {
            mustRunAfter("splitStdlib_$primaryAbi")
        }
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
            // `_sysconfigdata__android_<arch>` is ARCH-SPECIFIC: each ABI ships its
            // own (e.g. `_sysconfigdata__android_x86_64-linux-android`) and CPython
            // imports the one matching the running device at startup (sysconfig,
            // pulled in by ctypes). Since stdlib.zip is ABI-common and built from the
            // primary ABI only, harvest every other ABI's into it — otherwise a
            // non-primary ABI (e.g. an x86_64 emulator when arm64-v8a is primary)
            // crashes with `ModuleNotFoundError: _sysconfigdata__android_...`.
            //
            // Match ONLY the `_sysconfigdata__android_<arch>` files (unique per ABI),
            // not the generic, ABI-identical `_sysconfigdata__linux_` that some
            // versions (e.g. 3.12) also ship — the primary already added that via the
            // stdlib loop above, so harvesting it again would be a duplicate zip entry.
            if (isPrimary) {
                abis.filter { it != abi }.forEach { otherAbi ->
                    val otherBundle = File(file("src/main/jniLibs/$otherAbi"), "libpythonbundle.so")
                    if (otherBundle.exists()) {
                        ZipFile(otherBundle).use { ozf ->
                            val oen = ozf.entries()
                            while (oen.hasMoreElements()) {
                                val oe = oen.nextElement()
                                if (!oe.isDirectory &&
                                    oe.name.startsWith("stdlib/_sysconfigdata__android")
                                ) {
                                    zip?.add(
                                        oe.name.removePrefix("stdlib/"),
                                        ozf.getInputStream(oe).readBytes(),
                                    )
                                }
                            }
                        }
                    }
                }
            }
            zip?.add("_sp_bootstrap.py", bootstrapPy.readBytes())   // finder at zip root
            // The dart-bridge Android shim (F) installs the finder before `site`. A
            // sitecustomize fallback can be re-enabled for bridges without that shim:
            //   zip?.add("sitecustomize.py", "import _sp_bootstrap\n_sp_bootstrap.install()\n".toByteArray())
            zip?.synthesizePackageInits()
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
            siteZip?.synthesizePackageInits()
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
    // SERIOUS_PYTHON_DART_BRIDGE_DIST: local-dev override pointing at a dir of
    // freshly cross-compiled libdart_bridge-android-<abi>-py<ver>.so, bypassing the
    // GitHub release download (mirrors the SERIOUS_PYTHON_BUILD_DIST escape hatch).
    val dartBridgeDist = System.getenv("SERIOUS_PYTHON_DART_BRIDGE_DIST")
    val bridgeFile = if (dartBridgeDist != null)
        File(dartBridgeDist, "libdart_bridge-android-$abi-py$pythonVersion.so")
    else
        File(dartBridgeCacheDir, "libdart_bridge-android-$abi-py$pythonVersion.so")
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
        if (dartBridgeDist == null) dependsOn("downloadDartBridge_$abi")
        dependsOn("jniCleanUp_$abi")
    }
    packageTasks.add("copyDartBridge_$abi")
}

// The app's Python sources (already processed by serious_python's `package`
// command into SERIOUS_PYTHON_APP) ship as a STORED, ABI-common `app.zip`
// asset alongside stdlib.zip/sitepackages.zip; the plugin unpacks it to the
// files dir on first launch (version-keyed). Built once, regardless of ABI.
val appSrcDir: String? = System.getenv("SERIOUS_PYTHON_APP")
tasks.register("packageApp") {
    outputs.dir(assetsDir)
    outputs.upToDateWhen { false }
    doLast {
        if (appSrcDir == null || appSrcDir.isBlank()) return@doLast
        val appDir = File(appSrcDir)
        if (!appDir.isDirectory)
            throw GradleException("serious_python: SERIOUS_PYTHON_APP dir not found: $appSrcDir")
        val zip = storedZip(File(assetsDir, "app.zip"))
        appDir.walkTopDown().filter { it.isFile }.forEach { f ->
            val rel = f.relativeTo(appDir).path.replace(File.separatorChar, '/')
            zip.add(rel, f.readBytes())
        }
        zip.close()
    }
}

val copyOrUntar = tasks.register("copyOrUntar") {
    if (System.getenv("SERIOUS_PYTHON_BUILD_DIST") != null) {
        dependsOn("copyBuildDist")
    } else {
        dependsOn(packageTasks)
    }
}

tasks.named("preBuild") {
    dependsOn(copyOrUntar, "packageApp")
}
