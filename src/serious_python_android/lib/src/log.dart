import 'package:flutter/foundation.dart';

void spDebug(String message) {
  if (message.startsWith('[serious_python]')) {
    debugPrint(message);
  } else {
    debugPrint('[serious_python] $message');
  }
}

