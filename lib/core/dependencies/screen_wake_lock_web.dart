import 'dart:js_interop';

@JS('navigator.wakeLock')
external _WakeLock? get _wakeLock;

extension type _WakeLock(JSObject _) implements JSObject {
  external JSPromise<_WakeLockSentinel> request(JSString type);
}

extension type _WakeLockSentinel(JSObject _) implements JSObject {
  external JSBoolean get released;
  external JSPromise<JSAny?> release();
}

_WakeLockSentinel? _sentinel;

Future<void> setScreenWakeLock(bool enabled) async {
  if (enabled) {
    final current = _sentinel;
    if (current != null && !current.released.toDart) return;
    _sentinel = await _wakeLock?.request('screen'.toJS).toDart;
  } else {
    final current = _sentinel;
    _sentinel = null;
    if (current != null && !current.released.toDart) {
      await current.release().toDart;
    }
  }
}
