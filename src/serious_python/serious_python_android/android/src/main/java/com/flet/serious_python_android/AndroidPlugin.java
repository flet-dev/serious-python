package com.flet.serious_python_android;

import android.content.Context;
import android.content.ContextWrapper;
import androidx.annotation.NonNull;
import android.system.Os;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/** AndroidPlugin */
public class AndroidPlugin implements FlutterPlugin, MethodCallHandler {
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
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.equals("getPlatformVersion")) {
      result.success("Android " + android.os.Build.VERSION.RELEASE);
    } else if (call.method.equals("getNativeLibraryDir")) {
      ContextWrapper contextWrapper = new ContextWrapper(context);
      String nativeLibraryDir = contextWrapper.getApplicationInfo().nativeLibraryDir;
      result.success(nativeLibraryDir);
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
}
