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

/** AndroidPlugin */
public class AndroidPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {

  public static final String MAIN_ACTIVITY_HOST_CLASS_NAME = "MAIN_ACTIVITY_HOST_CLASS_NAME";
  public static final String MAIN_ACTIVITY_CLASS_NAME = "MAIN_ACTIVITY_CLASS_NAME";
  public static final String ANDROID_NATIVE_LIBRARY_DIR = "ANDROID_NATIVE_LIBRARY_DIR";

  /// The MethodChannel that will the communication between Flutter and native
  /// Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine
  /// and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;
  private Context context;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(),
        "android_plugin");
    channel.setMethodCallHandler(this);
    this.context = flutterPluginBinding.getApplicationContext();
    try {
      Os.setenv(ANDROID_NATIVE_LIBRARY_DIR, new ContextWrapper(this.context).getApplicationInfo().nativeLibraryDir, true);
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
    if (call.method.equals("getPlatformVersion")) {
      result.success("Android " + android.os.Build.VERSION.RELEASE);
    } else if (call.method.equals("getNativeLibraryDir")) {
      ContextWrapper contextWrapper = new ContextWrapper(context);
      String nativeLibraryDir = contextWrapper.getApplicationInfo().nativeLibraryDir;
      result.success(nativeLibraryDir);
    } else if (call.method.equals("loadLibrary")) {
      try {
        System.loadLibrary(call.argument("libname"));
        result.success(null);
      } catch (Throwable e) {
        result.error("Error", e.getMessage(), null);
      }
    } else if (call.method.equals("setEnvironmentVariable")) {
      String name = call.argument("name");
      String value = call.argument("value");
      try {
        Os.setenv(name, value, true);
        result.success(null);
      } catch (Exception e) {
        result.error("Error", e.getMessage(), null);
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
