package com.flet.serious_python_android;
import java.lang.*;
import android.content.Context;
import android.content.ContextWrapper;
import androidx.annotation.NonNull;
import android.system.Os;
import android.content.Intent;

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
      // the finder can dlopen them directly from the APK (mmap, no extraction).
      String abi = (android.os.Build.SUPPORTED_ABIS != null
          && android.os.Build.SUPPORTED_ABIS.length > 0)
          ? android.os.Build.SUPPORTED_ABIS[0] : "";
      Os.setenv("ANDROID_APK_NATIVE_PREFIX", ai.sourceDir + "!/lib/" + abi + "/", true);
    } catch (Exception e) {
      // nothing to do
    }
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
    } else if (call.method.equals("getNativeLibraryDir")) {
      ContextWrapper contextWrapper = new ContextWrapper(context);
      String nativeLibraryDir = contextWrapper.getApplicationInfo().nativeLibraryDir;
      result.success(nativeLibraryDir);
    } else if (call.method.equals("getFilesDir")) {
      result.success(context.getFilesDir().getAbsolutePath());
    } else if (call.method.equals("extractAsset")) {
      // Stream an APK asset to disk as one whole file (e.g. stdlib.zip).
      try {
        String asset = call.argument("asset");
        String dest = call.argument("dest");
        java.io.File destFile = new java.io.File(dest);
        if (destFile.getParentFile() != null) destFile.getParentFile().mkdirs();
        byte[] buf = new byte[1 << 16];
        try (java.io.InputStream in = context.getAssets().open(asset);
             java.io.OutputStream out = new java.io.FileOutputStream(destFile)) {
          int n;
          while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
        result.success(dest);
      } catch (Exception e) {
        result.error("extractAsset", e.getMessage(), null);
      }
    } else if (call.method.equals("unzipAsset")) {
      // Unpack an APK asset zip (e.g. extract.zip) into a directory tree.
      try {
        String asset = call.argument("asset");
        String destDir = call.argument("dest");
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
        result.success(destDir);
      } catch (Exception e) {
        result.error("unzipAsset", e.getMessage(), null);
      }
    } else {
      result.notImplemented();
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }

  @Override
  public void onDetachedFromActivity() {}

  @Override
  public void onDetachedFromActivityForConfigChanges() {}

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {}

}
