import 'dart:async';

import 'package:flet/flet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:serious_python/bridge.dart';
import 'package:serious_python/serious_python.dart';

const bool isProduction = bool.fromEnvironment('dart.vm.product');

const assetPath = "app/app.zip";
const pythonModuleName = "main";
final hideLoadingPage =
    bool.tryParse("{{ cookiecutter.hide_loading_animation }}".toLowerCase()) ??
        true;
const errorExitCode = 100;

/// The Python script is intentionally smaller than in `flet_example`. No
/// stdout-callback socket, no flet.sock — Python startup is just `runpy`
/// on the user module, and stdout/stderr stay attached to whatever the
/// embedded interpreter inherits. The dart_bridge transport in Flet 0.85+
/// handles IPC directly.
const pythonScript = """
import logging, os, runpy, sys, traceback

# Redirect stdout/stderr to a file under FLET_APP_TEMP so we can inspect what
# Python is doing without a separate stdout-callback socket. Temporary — once
# the FFI transport is stable a more proper logging story can land.
_log_path = os.path.join(
    os.environ.get("FLET_APP_TEMP", "/tmp"), "flet_ffi_boot.log"
)
_log = open(_log_path, "w", buffering=1)
sys.stdout = _log
sys.stderr = _log
logging.basicConfig(stream=_log, level=logging.DEBUG)
print(f"[boot] python {sys.version}", flush=True)
print(f"[boot] FLET_DART_BRIDGE_PORT={os.environ.get('FLET_DART_BRIDGE_PORT')}", flush=True)
print(f"[boot] FLET_PLATFORM={os.environ.get('FLET_PLATFORM')}", flush=True)

try:
    import certifi
    os.environ["REQUESTS_CA_BUNDLE"] = certifi.where()
    os.environ["SSL_CERT_FILE"] = certifi.where()

    if os.getenv("FLET_PLATFORM") == "android":
        import ssl

        def create_default_context(
            purpose=ssl.Purpose.SERVER_AUTH, *,
            cafile=None, capath=None, cadata=None,
        ):
            return ssl.create_default_context(
                purpose=purpose,
                cafile=certifi.where(),
                capath=capath,
                cadata=cadata,
            )

        ssl._create_default_https_context = create_default_context
except ImportError as e:
    print(f"[boot] certifi import failed: {e}", flush=True)

print("[boot] about to runpy.run_module", flush=True)
try:
    runpy.run_module("{module_name}", run_name="__main__")
    print("[boot] runpy.run_module returned", flush=True)
except SystemExit as e:
    print(f"[boot] SystemExit: {e.code}", flush=True)
    raise
except Exception:
    print("[boot] runpy.run_module raised:", flush=True)
    traceback.print_exc()
    sys.exit($errorExitCode)
""";

// global vars
String assetsDir = "";
String appDir = "";
late PythonBridge _bridge;
Map<String, String> environmentVariables = {};

void main() async {
  if (isProduction) {
    // ignore: avoid_returning_null_for_void
    debugPrint = (String? message, {int? wrapWidth}) => null;
  }

  runApp(FutureBuilder(
      future: prepareApp(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.hasData) {
          return FletApp(
            pageUrl: "dartbridge://${_bridge.port}",
            assetsDir: assetsDir,
            channelBuilder: ({required onMessage, required onDisconnect}) =>
                _DartBridgeBackendChannel(_bridge,
                    onMessage: onMessage, onDisconnect: onDisconnect),
          );
        } else if (snapshot.hasError) {
          return MaterialApp(
              home: ErrorScreen(
                  title: "Error starting app",
                  text: snapshot.error.toString()));
        } else {
          return const MaterialApp(home: BlankScreen());
        }
      }));
}

Future<String> prepareApp() async {
  if (kIsWeb) {
    var routeUrlStrategy = getFletRouteUrlStrategy();
    if (routeUrlStrategy == "path") {
      usePathUrlStrategy();
    }
    return "";
  }

  await setupDesktop();

  // Extract app from asset.
  appDir = await extractAssetZip(assetPath, checkHash: true);
  Directory.current = appDir;
  assetsDir = path.join(appDir, "assets");

  WidgetsFlutterBinding.ensureInitialized();
  var appTempPath = (await path_provider.getApplicationCacheDirectory()).path;
  var appDataPath =
      (await path_provider.getApplicationDocumentsDirectory()).path;

  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android) {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    appDataPath = path.join(appDataPath, "flet", packageInfo.packageName);
    if (!await Directory(appDataPath).exists()) {
      await Directory(appDataPath).create(recursive: true);
    }
  }

  // Create the PythonBridge before we hand its port to Python. It outlives
  // the FletApp widget; the embedded interpreter only stops when the Flutter
  // app exits.
  _bridge = PythonBridge();

  environmentVariables.addAll({
    "FLET_APP_DATA": appDataPath,
    "FLET_APP_TEMP": appTempPath,
    "FLET_PLATFORM": defaultTargetPlatform.name.toLowerCase(),
    // Python reads this env var in flet.app.run_async() and starts the
    // dart_bridge transport (added in flet's dart-bridge branch) bound to
    // the same port.
    "FLET_DART_BRIDGE_PORT": "${_bridge.port}",
  });

  // Fire-and-forget: Python lives for the duration of the app. SeriousPython
  // dispatches it on a worker thread (sync=false default), so this returns
  // immediately after spawning.
  var script = pythonScript.replaceAll('{module_name}', pythonModuleName);
  unawaited(SeriousPython.runProgram(
    path.join(appDir, "$pythonModuleName.pyc"),
    script: script,
    environmentVariables: environmentVariables,
  ));

  return "";
}

/// `FletBackendChannel` implementation backed by a [PythonBridge]. Bytes
/// flow Dart↔Python entirely in-process; no Unix socket, no kernel context
/// switch. The wire format is the same MsgPack-framed protocol the existing
/// socket-based `FletSocketBackendChannel` speaks.
class _DartBridgeBackendChannel implements FletBackendChannel {
  _DartBridgeBackendChannel(this._bridge,
      {required FletBackendChannelOnMessageCallback onMessage,
      required FletBackendChannelOnDisconnectCallback onDisconnect})
      : _onMessage = onMessage,
        _onDisconnect = onDisconnect,
        _deserializer =
            StreamingMsgpackDeserializer(extDecoder: FletMsgpackDecoder());

  final PythonBridge _bridge;
  final FletBackendChannelOnMessageCallback _onMessage;
  final FletBackendChannelOnDisconnectCallback _onDisconnect;
  final StreamingMsgpackDeserializer _deserializer;
  StreamSubscription<Uint8List>? _subscription;

  @override
  Future connect() async {
    _subscription = _bridge.messages.listen(
      _onBytes,
      onError: (error, stack) {
        debugPrint("PythonBridge stream error: $error");
        _onDisconnect();
      },
      onDone: () {
        debugPrint("PythonBridge stream closed.");
        _onDisconnect();
      },
      cancelOnError: false,
    );
  }

  void _onBytes(Uint8List bytes) {
    _deserializer.addChunk(bytes);
    final frames = _deserializer.decodeMessages();
    for (final frame in frames) {
      _onMessage(Message.fromList(frame));
    }
  }

  @override
  void send(Message message) {
    final encoded = Uint8List.fromList(
        msgpack.serialize(message.toList(), extEncoder: FletMsgpackEncoder()));
    // Retry loop covers the brief startup window where Python hasn't yet
    // called dart_bridge.set_enqueue_handler_func — bridge.send returns
    // false in that case. Once the handler is registered (Flet's app.py
    // dart_bridge server start() does it before run_module dispatch),
    // bridge.send returns true synchronously.
    if (_bridge.send(encoded)) return;
    _retrySend(encoded);
  }

  void _retrySend(Uint8List encoded) {
    const interval = Duration(milliseconds: 50);
    const deadline = Duration(seconds: 30);
    final start = DateTime.now();
    Timer.periodic(interval, (timer) {
      if (_bridge.send(encoded)) {
        timer.cancel();
      } else if (DateTime.now().difference(start) > deadline) {
        timer.cancel();
        debugPrint("PythonBridge send timed out: Python handler never registered.");
      }
    });
  }

  @override
  bool get isLocalConnection => true;

  @override
  int get defaultReconnectIntervalMs => 0;

  @override
  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
  }
}

class ErrorScreen extends StatelessWidget {
  final String title;
  final String text;

  const ErrorScreen({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                  icon: const Icon(
                    Icons.copy,
                    size: 16,
                  ),
                  label: const Text("Copy"),
                )
              ],
            ),
            Expanded(
                child: SingleChildScrollView(
              child: SelectableText(text,
                  style: Theme.of(context).textTheme.bodySmall),
            ))
          ],
        ),
      )),
    );
  }
}

class BlankScreen extends StatelessWidget {
  const BlankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}
