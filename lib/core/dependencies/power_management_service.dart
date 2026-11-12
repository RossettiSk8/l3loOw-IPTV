import 'dart:async';

import 'package:flutter/widgets.dart';

import 'memory_cache_service.dart';
import 'screen_wake_lock.dart';

final class PowerManagementService with WidgetsBindingObserver {
  PowerManagementService({
    this.onSuspendNetwork,
    this.onResumeNetwork,
    Future<void> Function(bool)? wakeLock,
    MemoryCacheService? imageCache,
  }) : _wakeLock = wakeLock ?? setScreenWakeLock,
       _imageCache = imageCache ?? MemoryCacheService(),
       _binding = WidgetsBinding.instance {
    // Un árbol que se monta antes de la primera notificación puede empezar a reproducir.
    _state = _binding.lifecycleState ?? AppLifecycleState.resumed;
    _binding.addObserver(this);
  }

  final VoidCallback? onSuspendNetwork;
  final VoidCallback? onResumeNetwork;
  final Future<void> Function(bool) _wakeLock;
  final WidgetsBinding _binding;
  final MemoryCacheService _imageCache;
  final _listeners = <VoidCallback>{};
  final _activePlayers = <Object>{};
  late AppLifecycleState _state;
  bool _desiredWake = false;
  Future<void> _wakeChanges = Future.value();

  bool get allowsPlayback =>
      _state == AppLifecycleState.resumed ||
      _state == AppLifecycleState.inactive;

  void addPlaybackListener(VoidCallback listener) => _listeners.add(listener);
  void removePlaybackListener(VoidCallback listener) =>
      _listeners.remove(listener);

  void setPlaybackActive(Object session, bool active) {
    if (active && allowsPlayback) {
      _activePlayers.add(session);
    } else {
      _activePlayers.remove(session);
    }
    _syncWakeLock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = allowsPlayback;
    _state = state;
    if (!allowsPlayback) {
      _activePlayers.clear();
      if (wasForeground || state == AppLifecycleState.detached) {
        onSuspendNetwork?.call();
        didHaveMemoryPressure();
      }
    } else if (!wasForeground) {
      onResumeNetwork?.call();
    }
    _syncWakeLock();
    if (wasForeground != allowsPlayback) {
      for (final listener in _listeners.toList(growable: false)) {
        listener();
      }
    }
  }

  @override
  void didHaveMemoryPressure() => _imageCache.trim();

  void _syncWakeLock() {
    final desired =
        _state == AppLifecycleState.resumed && _activePlayers.isNotEmpty;
    if (desired == _desiredWake) return;
    _desiredWake = desired;
    _wakeChanges = _wakeChanges.then((_) async {
      if (desired != _desiredWake) return;
      try {
        await _wakeLock(desired);
      } catch (_) {
        // La plataforma puede retirar el permiso al cambiar la visibilidad.
      }
    });
  }

  void dispose() {
    _binding.removeObserver(this);
    _listeners.clear();
    _activePlayers.clear();
    _syncWakeLock();
  }
}
