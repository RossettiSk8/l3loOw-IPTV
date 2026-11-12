import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('l3loow/screen_wake_lock');

Future<void> setScreenWakeLock(bool enabled) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  await _channel.invokeMethod<void>('setEnabled', enabled);
}
