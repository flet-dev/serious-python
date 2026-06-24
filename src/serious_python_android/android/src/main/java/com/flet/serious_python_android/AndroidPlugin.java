package com.flet.serious_python_android;
import java.lang.*;
import android.content.Context;
import android.content.ContextWrapper;
import androidx.annotation.NonNull;
import android.system.Os;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import com.flet.serious_python_android.PythonActivity;

/**
 * Thin Flutter plugin: surfaces nativeLibraryDir and app version to Dart and
 * exposes a few process-wide env vars Python code may read. All Python
 * lifecycle now lives in libdart_bridge.so (downloaded from
 * flet-dev/dart-bridge), invoked from Dart via FFI.
 */
public class AndroidPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {

  public static final String MAIN_ACTIVITY_HOST_CLASS_NAME = "MAIN_ACTIVITY_HOST_CLASS_NAME";
  public static final String MAIN_ACTIVITY_CLASS_NAME = "MAIN_ACTIVITY_CLASS_NAME";
  public static final String ANDROID_NATIVE_LIBRARY_DIR = "ANDROID_NATIVE_LIBRARY_DIR";

  private MethodChannel channel;
  private Context context;

  // Heavy native work (asset extraction/unzipping, native library loading) must
  // NOT run on the platform main thread: it would block Android's Choreographer
  // and starve Flutter's vsync, freezing on-screen animations (e.g. the boot
  // spinner). Run it on a background executor and post the MethodChannel result
  // back on the main thread (Flutter requires result callbacks there).
  private final ExecutorService ioExecutor = Executors.newSingleThreadExecutor();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private void runAsync(@NonNull Result result, String errorCode, Callable<Object> work) {
    ioExecutor.execute(() -> {
      try {
        Object value = work.call();
        mainHandler.post(() -> result.success(value));
      } catch (Throwable e) {
        mainHandler.post(() -> result.error(errorCode, e.getMessage(), null));
      }
    });
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(),
        "android_plugin");
    channel.setMethodCallHandler(this);
    this.context = flutterPluginBinding.getApplicationContext();
    try {
      android.content.pm.ApplicationInfo ai =
          new ContextWrapper(this.context).getApplicationInfo();
      Os.setenv(ANDROID_NATIVE_LIBRARY_DIR, ai.nativeLibraryDir, true);
      // Under modern packaging (useLegacyPackaging=false) native libs are NOT extracted
      // to nativeLibraryDir; they live uncompressed/page-aligned inside the APK and are
      // loadable via Bionic's zip-path (apk!/lib/<abi>/<soname>). Export that prefix so
      // the finder can dlopen them directly from the APK (mmap, no extraction). For Play
      // Store AAB installs the libs are in a per-ABI config split, not base.apk, so pick
      // whichever installed APK actually contains lib/<abi>/.
      String abi = (android.os.Build.SUPPORTED_ABIS != null
          && android.os.Build.SUPPORTED_ABIS.length > 0)
          ? android.os.Build.SUPPORTED_ABIS[0] : "";
      Os.setenv("ANDROID_APK_NATIVE_PREFIX", apkNativePrefix(ai, abi), true);
    } catch (Exception e) {
      // nothing to do
    }
  }

  // Bionic zip-path prefix (<apk>!/lib/<abi>/) of the installed APK that holds the
  // native libs. Single-APK builds -> base.apk; Play Store AAB installs -> the
  // per-ABI config split (base.apk has no libs then). Detected by probing for the
  // always-present libdart_bridge.so.
  private static String apkNativePrefix(android.content.pm.ApplicationInfo ai, String abi) {
    java.util.List<String> apks = new java.util.ArrayList<>();
    if (ai.sourceDir != null) apks.add(ai.sourceDir);
    if (ai.splitSourceDirs != null) {
      java.util.Collections.addAll(apks, ai.splitSourceDirs);
    }
    String member = "lib/" + abi + "/libdart_bridge.so";
    for (String apk : apks) {
      try (java.util.zip.ZipFile zf = new java.util.zip.ZipFile(apk)) {
        if (zf.getEntry(member) != null) {
          return apk + "!/lib/" + abi + "/";
        }
      } catch (Exception e) {
        // unreadable apk — skip
      }
    }
    return (ai.sourceDir != null ? ai.sourceDir : "") + "!/lib/" + abi + "/";
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding activityPluginBinding) {
    PythonActivity.mActivity = activityPluginBinding.getActivity();
    try {
      Os.setenv(MAIN_ACTIVITY_HOST_CLASS_NAME, PythonActivity.class.getCanonicalName(), true);
      Os.setenv(MAIN_ACTIVITY_CLASS_NAME, PythonActivity.mActivity.getClass().getCanonicalName(), true);
    } catch (Exception e) {
      // nothing to do
    }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.equals("getAppVersion")) {
      try {
        String packageName = context.getPackageName();
        android.content.pm.PackageManager pm = context.getPackageManager();
        android.content.pm.PackageInfo info = pm.getPackageInfo(packageName, 0);
        String versionName = info.versionName;
        long versionCode = info.getLongVersionCode();
        result.success(versionName + "+" + versionCode);
      } catch (Exception e) {
        result.error("Error", e.getMessage(), null);
      }
    } else if (call.method.equals("loadLibrary")) {
      // Load a native library by name via Java's System.loadLibrary(), which —
      // unlike dart:ffi's dlopen-based DynamicLibrary.open used for
      // libdart_bridge — runs the library's JNI_OnLoad. That's how pyjnius's
      // helper (libpyjni.so) captures the JavaVM + app ClassLoader. Called from
      // app code here, so JNI_OnLoad sees the app's class loader.
      //
      // MUST stay on the platform main thread. Loading off a background thread
      // (even with the worker's context ClassLoader pinned to the app loader)
      // breaks pyjnius — its JNI_OnLoad relies on running on the main thread.
      try {
        System.loadLibrary((String) call.argument("libname"));
        result.success(null);
      } catch (Throwable e) {
        result.error("loadLibrary", e.getMessage(), null);
      }
    } else if (call.method.equals("extractAsset")) {
      // Stream an APK asset to disk as one whole file (e.g. stdlib.zip).
      final String asset = call.argument("asset");
      final String dest = call.argument("dest");
      runAsync(result, "extractAsset", () -> {
        java.io.File destFile = new java.io.File(dest);
        if (destFile.getParentFile() != null) destFile.getParentFile().mkdirs();
        byte[] buf = new byte[1 << 16];
        try (java.io.InputStream in = context.getAssets().open(asset);
             java.io.OutputStream out = new java.io.FileOutputStream(destFile)) {
          int n;
          while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
        return dest;
      });
    } else if (call.method.equals("unzipAsset")) {
      // Unpack an APK asset zip (e.g. extract.zip) into a directory tree.
      final String asset = call.argument("asset");
      final String destDir = call.argument("dest");
      runAsync(result, "unzipAsset", () -> {
        java.io.File root = new java.io.File(destDir);
        byte[] buf = new byte[1 << 16];
        try (java.io.InputStream in = context.getAssets().open(asset);
             java.util.zip.ZipInputStream zis = new java.util.zip.ZipInputStream(in)) {
          java.util.zip.ZipEntry e;
          while ((e = zis.getNextEntry()) != null) {
            java.io.File f = new java.io.File(root, e.getName());
            if (e.isDirectory()) {
              f.mkdirs();
            } else {
              if (f.getParentFile() != null) f.getParentFile().mkdirs();
              try (java.io.OutputStream out = new java.io.FileOutputStream(f)) {
                int n;
                while ((n = zis.read(buf)) > 0) out.write(buf, 0, n);
              }
            }
          }
        }
        return destDir;
      });
    } else {
      result.notImplemented();
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    ioExecutor.shutdown();
  }

  @Override
  public void onDetachedFromActivity() {}

  @Override
  public void onDetachedFromActivityForConfigChanges() {}

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {}

}
