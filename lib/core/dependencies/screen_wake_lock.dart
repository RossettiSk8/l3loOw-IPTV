import 'screen_wake_lock_native.dart'
    if (dart.library.js_interop) 'screen_wake_lock_web.dart'
    as platform;

Future<void> setScreenWakeLock(bool enabled) =>
    platform.setScreenWakeLock(enabled);
