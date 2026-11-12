import 'dart:async';
import 'dart:math' as math;

// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/dependencies/media_player_optimizer.dart';
import '../../core/dependencies/power_management_service.dart';
import '../../domain/contracts/subtitle_repository.dart';
import '../../domain/entities/stream_chain_result.dart';
import '../../domain/entities/stream_option.dart';
import '../../domain/entities/subtitle_track.dart';
import '../../domain/repositories/playback_quality.dart';
import '../../domain/repositories/stream_startup_policy.dart';
import '../widgets/power_management_scope.dart';
import '../widgets/streaming_theme.dart';
import '../widgets/tv_action.dart';

final class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.title,
    required this.source,
    required this.sources,
    required this.providerNames,
    required this.subtitles,
    this.isLive = false,
    this.automaticStartup = false,
    super.key,
  });

  final String title;
  final StreamOption source;
  final List<StreamOption> sources;
  final Map<String, String> providerNames;
  final SubtitleRepository subtitles;
  final bool isLive;
  final bool automaticStartup;

  static Future<void> openMedia(
    BuildContext context, {
    required String title,
    required StreamOption source,
    required StreamChainResult result,
    required SubtitleRepository subtitles,
    bool automaticStartup = false,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PlayerScreen(
        title: title,
        source: source,
        sources: automaticStartup
            ? result.startupOptions
            : result.playableOptions,
        providerNames: result.providerNames,
        subtitles: subtitles,
        automaticStartup: automaticStartup,
      ),
    ),
  );

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _timelineFocus = FocusNode(debugLabel: 'Posición del video');
  final _qualityPolicy = ProgressiveQualityPolicy();
  final _startupPolicy = const StreamStartupPolicy();
  final _clock = Stopwatch()..start();
  final _unavailable = <Uri>{};
  final _controllers = <VideoPlayerController>{};
  final _pendingPlays = <VideoPlayerController, Future<void>>{};
  VoidCallback? _cancelPreparation;
  PowerManagementService? _power;
  bool _ownsPower = false;
  Completer<void> _suspended = Completer<void>();
  late StreamOption _source = widget.source;
  late VideoPlayerController _player = _createPlayer(_source);
  late QualityMode _mode = _source.isAdaptive
      ? QualityMode.automatic
      : QualityMode.manual;
  Timer? _adaptiveTimer;
  SubtitleTrack? _subtitle;
  ClosedCaptionFile? _captions;
  double? _seekPreview;
  int _seekRevision = 0;
  bool _busy = true;
  bool _starting = true;
  bool _tryingAlternative = false;
  bool _picking = false;
  bool _failed = false;
  bool _playRejected = false;
  bool _playRequested = false;
  bool _interrupted = false;

  List<StreamOption> get _sources => {
    for (final source in widget.sources) source.url: source,
    _source.url: _source,
  }.values.toList();

  VideoPlayerController _createPlayer(StreamOption source) {
    final controller = MediaPlayerOptimizer.createController(source);
    _controllers.add(controller);
    return controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_power != null) return;
    final shared = PowerManagementScope.maybeOf(context);
    final power = shared ?? PowerManagementService();
    _ownsPower = shared == null;
    _power = power;
    power.addPlaybackListener(_onPlaybackLifecycle);
    _player.addListener(_updateWakeLock);
    if (power.allowsPlayback) {
      unawaited(_initialize());
    } else {
      _suspended.complete();
      _starting = false;
      _busy = false;
      _interrupted = true;
    }
  }

  void _updateWakeLock() {
    final value = _player.value;
    if (_adaptiveTimer != null && (value.isCompleted || value.hasError)) {
      _stopAdaptation();
    }
    _power?.setPlaybackActive(
      this,
      _playRequested &&
          !_playRejected &&
          value.isInitialized &&
          value.isPlaying &&
          !value.isBuffering &&
          !value.isCompleted &&
          !value.hasError,
    );
  }

  void _setPlayer(VideoPlayerController player) {
    _player.removeListener(_updateWakeLock);
    _player = player;
    _player.addListener(_updateWakeLock);
    _updateWakeLock();
  }

  void _onPlaybackLifecycle() {
    if (_power!.allowsPlayback) {
      if (_suspended.isCompleted) _suspended = Completer<void>();
      return;
    }
    if (!_suspended.isCompleted) _suspended.complete();
    _cancelPreparation?.call();
    _stopAdaptation();
    final player = _player;
    final wasStarting = _starting;
    final shouldPause = player.value.isInitialized && player.value.isPlaying;
    setState(() {
      _playRequested = false;
      _playRejected = false;
      if (wasStarting) {
        _setPlayer(_createPlayer(_source));
        _starting = false;
        _busy = false;
        _interrupted = true;
      }
    });
    _updateWakeLock();
    if (wasStarting) {
      unawaited(_release(player));
    } else if (shouldPause) {
      unawaited(_pauseForBackground(player));
    }
  }

  Future<void> _pauseForBackground(VideoPlayerController player) async {
    try {
      await player.pause();
    } catch (_) {
      // La sesión puede haberse cerrado al separar la vista nativa.
    }
  }

  Future<bool> _prepare(VideoPlayerController player, Duration timeout) {
    final ready = Completer<bool>();
    final timer = Timer(timeout, () {
      ready.completeError(
        TimeoutException('El video no se inicializó a tiempo.', timeout),
      );
    });
    void cancel() {
      timer.cancel();
      if (!ready.isCompleted) ready.complete(false);
    }

    _cancelPreparation = cancel;
    unawaited(
      player.initialize().then(
        (_) {
          timer.cancel();
          if (!ready.isCompleted) ready.complete(true);
        },
        onError: (Object error, StackTrace stackTrace) {
          timer.cancel();
          if (!ready.isCompleted) ready.completeError(error, stackTrace);
        },
      ),
    );
    return ready.future.whenComplete(() {
      if (identical(_cancelPreparation, cancel)) _cancelPreparation = null;
    });
  }

  void _stopAdaptation() {
    _adaptiveTimer?.cancel();
    _adaptiveTimer = null;
    _qualityPolicy.reset();
  }

  @override
  void dispose() {
    _stopAdaptation();
    if (!_suspended.isCompleted) _suspended.complete();
    _cancelPreparation?.call();
    _power?.removePlaybackListener(_onPlaybackLifecycle);
    _power?.setPlaybackActive(this, false);
    if (_ownsPower) _power?.dispose();
    _player.removeListener(_updateWakeLock);
    _clock.stop();
    _timelineFocus.dispose();
    for (final controller in _controllers.toList(growable: false)) {
      unawaited(_release(controller));
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    final suspension = _suspended;
    final startedAt = _clock.elapsed;
    final candidates = _startupPolicy.candidates(
      widget.source,
      widget.sources,
      automatic: widget.automaticStartup,
    );
    for (final (index, source) in candidates.indexed) {
      if (!mounted || suspension.isCompleted) return;
      final timeout = _startupPolicy.timeout(
        source,
        elapsed: _clock.elapsed - startedAt,
        remainingAlternatives: candidates.length - index - 1,
      );
      if (timeout == Duration.zero) break;
      if (index > 0) _replaceStartupSource(source);
      final player = _player;
      try {
        if (!await _prepare(player, timeout)) return;
      } catch (_) {
        if (suspension.isCompleted) return;
        _unavailable.add(source.url);
        continue;
      }
      if (!mounted || suspension.isCompleted) return;
      if (player.value.hasError) {
        _unavailable.add(source.url);
        continue;
      }
      if (ModalRoute.of(context)?.isCurrent == true) await _start(player);
      if (mounted && !suspension.isCompleted) {
        setState(() {
          _busy = false;
          _starting = false;
        });
      }
      return;
    }
    if (mounted && !suspension.isCompleted) {
      final failed = _player;
      setState(() {
        _setPlayer(_createPlayer(_source));
        _failed = true;
        _busy = false;
        _starting = false;
      });
      unawaited(_release(failed));
    }
  }

  void _replaceStartupSource(StreamOption source) {
    final previous = _player;
    setState(() {
      _setPlayer(_createPlayer(source));
      _source = source;
      _mode = source.isAdaptive ? QualityMode.automatic : QualityMode.manual;
      _tryingAlternative = source.url != widget.source.url;
      _playRequested = false;
      _playRejected = false;
    });
    unawaited(_release(previous));
  }

  void _retryStartup() {
    if (_busy || !_power!.allowsPlayback) return;
    _stopAdaptation();
    _replaceStartupSource(widget.source);
    _unavailable.clear();
    setState(() {
      _failed = false;
      _busy = true;
      _starting = true;
      _interrupted = false;
      _subtitle = null;
      _captions = null;
      _seekPreview = null;
      _seekRevision++;
    });
    unawaited(_initialize());
  }

  Future<void> _release(VideoPlayerController player) async {
    if (!_controllers.remove(player)) return;
    final pending = _pendingPlays.remove(player);
    if (pending != null) {
      // La orden de pausa desbloquea el play pendiente en el motor web.
      unawaited(_pauseForBackground(player));
      try {
        await pending.timeout(const Duration(seconds: 1));
      } catch (_) {
        // La destrucción de la sesión también cancela la reproducción nativa.
      }
    }
    try {
      await player.dispose();
    } catch (_) {
      // La sesión puede no haberse creado si falló la inicialización.
    }
  }

  Future<void> _start(VideoPlayerController player) async {
    final suspension = _suspended;
    if (suspension.isCompleted || _pendingPlays.containsKey(player)) return;
    try {
      final pending = player.play();
      _pendingPlays[player] = pending;
      await pending;
      if (!mounted || !identical(player, _player)) return;
      if (suspension.isCompleted) {
        await _pauseForBackground(player);
        return;
      }
      if (!_playRequested || _playRejected) {
        setState(() {
          _playRequested = true;
          _playRejected = false;
        });
      }
      _updateWakeLock();
      if (_adaptiveTimer == null) _configureAdaptation();
    } catch (_) {
      if (mounted && !suspension.isCompleted && identical(player, _player)) {
        setState(() => _playRejected = true);
        _updateWakeLock();
      }
    } finally {
      _pendingPlays.remove(player);
    }
  }

  Future<void> _togglePlayback() async {
    if (_busy || !_power!.allowsPlayback) return;
    if (_interrupted) {
      _retryStartup();
      return;
    }
    if (_playRequested && !_playRejected && !_player.value.isCompleted) {
      try {
        await _player.pause();
        if (mounted) setState(() => _playRequested = false);
        _stopAdaptation();
      } catch (_) {
        _message('No se pudo pausar el video.');
      }
    } else {
      await _start(_player);
    }
  }

  Future<void> _seek(double milliseconds) async {
    if (_busy) return;
    _qualityPolicy.reset();
    final player = _player;
    final revision = ++_seekRevision;
    setState(() => _seekPreview = milliseconds);
    try {
      await player.seekTo(Duration(milliseconds: milliseconds.round()));
    } catch (_) {
      if (revision == _seekRevision) {
        _message('No se pudo cambiar la posición.');
      }
    } finally {
      if (mounted && revision == _seekRevision) {
        setState(() => _seekPreview = null);
      }
    }
  }

  Future<void> _chooseQuality() async {
    if (_busy) return;
    final sources = _sources;
    final manual = manualQualityOptions(
      sources,
    ).where((source) => source.height != null).toList();
    final automatic = [_source, ...sources].where((source) {
      return source.isAdaptive ||
          progressiveVariants(
                source,
                sources,
              ).map((variant) => variant.height).toSet().length >
              1;
    }).firstOrNull;
    final mode = await _pick('Modo de calidad', [
      _Choice(
        QualityMode.automatic,
        'Automático',
        detail: automatic == null
            ? 'Requiere un manifiesto o variantes del mismo montaje.'
            : 'Se adapta a la red y al búfer.',
        enabled: automatic != null,
        selected: _mode == QualityMode.automatic,
      ),
      _Choice(
        QualityMode.manual,
        'Manual',
        detail: manual.isNotEmpty
            ? 'Fija la calidad del enlace seleccionado.'
            : 'Los enlaces disponibles no anuncian una resolución fija.',
        enabled: manual.isNotEmpty,
        selected: _mode == QualityMode.manual,
      ),
    ]);
    if (!mounted || _busy || mode == null) return;
    if (mode == QualityMode.automatic && automatic != null) {
      _unavailable.clear();
      await _selectQuality(automatic, mode);
      return;
    }
    final selected = await _pick('Resolución manual', [
      for (final source in manual)
        _Choice(
          source,
          '${source.qualityLabel} · ${widget.providerNames[source.providerId] ?? source.providerId}',
          selected: source.url == _source.url,
        ),
    ]);
    if (mounted && selected != null) {
      await _selectQuality(selected, QualityMode.manual);
    }
  }

  Future<void> _selectQuality(StreamOption source, QualityMode mode) async {
    if (_busy) return;
    if (source.url != _source.url || _failed || _player.value.hasError) {
      await _switchSource(source, mode: mode);
    } else {
      setState(() => _mode = mode);
      _configureAdaptation();
    }
  }

  void _configureAdaptation() {
    _stopAdaptation();
    if (_power!.allowsPlayback &&
        _playRequested &&
        _mode == QualityMode.automatic &&
        !_source.isAdaptive) {
      _adaptiveTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _adapt(),
      );
    }
  }

  Future<void> _adapt() async {
    final value = _player.value;
    if (!_power!.allowsPlayback ||
        _busy ||
        _picking ||
        !_playRequested ||
        _playRejected ||
        !value.isInitialized ||
        value.hasError ||
        value.isCompleted ||
        (!value.isPlaying && !value.isBuffering) ||
        (value.buffered.isEmpty && !value.isBuffering)) {
      _qualityPolicy.reset();
      return;
    }
    final variants = progressiveVariants(
      _source,
      _sources,
    ).where((source) => !_unavailable.contains(source.url)).toList();
    var bufferedUntil = value.position;
    for (final range in value.buffered) {
      if (range.start <= value.position && range.end > bufferedUntil) {
        bufferedUntil = range.end;
      }
    }
    final next = _qualityPolicy.sample(
      current: _source,
      variants: variants,
      now: _clock.elapsed,
      position: value.position,
      bufferedUntil: bufferedUntil,
      duration: value.duration,
      isBuffering: value.isBuffering,
    );
    if (next == null) return;
    if (!await _switchSource(
          next,
          mode: QualityMode.automatic,
          requireAligned: true,
        ) &&
        mounted) {
      _unavailable.add(next.url);
      _qualityPolicy.reset();
    }
  }

  Future<bool> _switchSource(
    StreamOption source, {
    required QualityMode mode,
    bool requireAligned = false,
  }) async {
    if (_busy || !_power!.allowsPlayback) return false;
    final suspension = _suspended;
    setState(() => _busy = true);
    final previous = _player;
    final next = _createPlayer(source);
    var switched = false;
    try {
      if (!await _prepare(next, const Duration(seconds: 20))) {
        return false;
      }
      if (!mounted || suspension.isCompleted) return false;
      if (requireAligned &&
          (next.value.duration <= Duration.zero ||
              (next.value.duration - previous.value.duration).abs() >
                  const Duration(seconds: 3))) {
        return false;
      }
      final subtitle = _subtitle;
      final retainedSubtitle = subtitle == null
          ? null
          : source.subtitles
                .where((track) => track.url == subtitle.url)
                .firstOrNull;
      if (retainedSubtitle != null && _captions != null) {
        await next.setClosedCaptionFile(Future.value(_captions!));
      }
      if (!mounted || suspension.isCompleted) return false;
      final position = previous.value.position;
      final duration = next.value.duration;
      if (position > Duration.zero && duration > Duration.zero) {
        await next.seekTo(position < duration ? position : duration);
      }
      if (!mounted || suspension.isCompleted) return false;
      final wasPlaying =
          (_playRequested || previous.value.isPlaying) &&
          !_playRejected &&
          !previous.value.isCompleted;
      final shouldPlay = wasPlaying || _failed || previous.value.hasError;
      if (wasPlaying && !previous.value.hasError) await previous.pause();
      if (!mounted || suspension.isCompleted) return false;
      setState(() {
        _setPlayer(next);
        _source = source;
        _mode = mode;
        _failed = false;
        _playRejected = false;
        _subtitle = retainedSubtitle;
        if (retainedSubtitle == null) _captions = null;
        _seekPreview = null;
        _seekRevision++;
      });
      switched = true;
      _configureAdaptation();
      unawaited(_release(previous));
      if (shouldPlay) await _start(next);
    } catch (_) {
      if (!requireAligned && !suspension.isCompleted) {
        _message('No se pudo abrir esa fuente. Se conservó la anterior.');
      }
    } finally {
      if (!switched) unawaited(_release(next));
      if (mounted) setState(() => _busy = false);
    }
    return switched;
  }

  Future<void> _chooseAudio() async {
    if (_busy) return;
    final player = _player;
    try {
      final tracks = player.isAudioTrackSupportAvailable()
          ? await player.getAudioTracks()
          : const <VideoAudioTrack>[];
      if (!mounted || !identical(player, _player)) return;
      if (tracks.isEmpty) {
        _message(
          'Este enlace no ofrece pistas de audio seleccionables en este dispositivo.',
        );
        return;
      }
      final selected = await _pick('Pistas de audio', [
        for (var index = 0; index < tracks.length; index++)
          _Choice(
            tracks[index].id,
            tracks[index].label ??
                tracks[index].language ??
                'Pista ${index + 1}',
            selected: tracks[index].isSelected,
          ),
      ]);
      if (mounted && !_busy && selected != null && identical(player, _player)) {
        await player.selectAudioTrack(selected);
      }
    } catch (_) {
      _message('No se pudo cambiar la pista de audio.');
    }
  }

  Future<void> _chooseSubtitles() async {
    if (_busy) return;
    final tracks = _source.subtitles;
    if (tracks.isEmpty) {
      _message('Este enlace no incluye subtítulos externos.');
      return;
    }
    final source = _source;
    final selected = await _pick('Subtítulos', [
      _Choice(-1, 'Desactivados', selected: _subtitle == null),
      for (var index = 0; index < tracks.length; index++)
        _Choice(
          index,
          tracks[index].label ?? tracks[index].language,
          selected: _subtitle?.url == tracks[index].url,
        ),
    ]);
    if (!mounted || _busy || selected == null || !identical(source, _source)) {
      return;
    }
    final track = selected < 0 ? null : tracks[selected];
    if (track?.url == _subtitle?.url) return;
    setState(() => _busy = true);
    try {
      ClosedCaptionFile? file;
      if (track != null) {
        final text = await widget.subtitles.read(track);
        file = text.startsWith('WEBVTT')
            ? WebVTTCaptionFile(text)
            : SubRipCaptionFile(text);
        if (file.captions.isEmpty) {
          throw const FormatException(
            'El archivo no contiene subtítulos SRT o WebVTT.',
          );
        }
      }
      if (!mounted) return;
      await _player.setClosedCaptionFile(
        file == null ? null : Future.value(file),
      );
      if (mounted) {
        setState(() {
          _subtitle = track;
          _captions = file;
        });
      }
    } catch (_) {
      _message('No se pudieron cargar los subtítulos.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T?> _pick<T>(String title, List<_Choice<T>> choices) async {
    if (_picking || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return null;
    }
    final active = choices.indexWhere(
      (choice) => choice.enabled && choice.selected,
    );
    final initial = active < 0
        ? choices.indexWhere((choice) => choice.enabled)
        : active;
    _picking = true;
    try {
      return await showDialog<T>(
        context: context,
        builder: (_) =>
            _ChoiceDialog(title: title, choices: choices, initial: initial),
      );
    } finally {
      _picking = false;
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _player,
        builder: (context, value, _) {
          final failed = !_starting && (_failed || value.hasError);
          final ready = value.isInitialized && !value.hasError && !_failed;
          final playing =
              ready && _playRequested && !_playRejected && !value.isCompleted;
          final duration = value.duration.inMilliseconds.toDouble();
          final position =
              (_seekPreview ?? value.position.inMilliseconds.toDouble())
                  .clamp(0.0, duration)
                  .toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              if (ready)
                Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio,
                    child: VideoPlayer(_player, key: ObjectKey(_player)),
                  ),
                )
              else if (failed)
                const Center(child: Text('No se pudo reproducir este enlace.')),
              if (!failed && (_starting || (playing && value.isBuffering)))
                Center(
                  child: _BufferingStatus(
                    message: _starting
                        ? (_tryingAlternative
                              ? 'Probando otra fuente…'
                              : 'Conectando con la fuente…')
                        : 'Cargando video…',
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ready && value.caption.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ClosedCaption(text: value.caption.text),
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: StreamingPalette.glass,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  if (widget.isLive)
                                    const Text('En vivo')
                                  else if (ready && duration > 0)
                                    Row(
                                      children: [
                                        Text(
                                          _time(
                                            Duration(
                                              milliseconds: position.round(),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: AnimatedBuilder(
                                            animation: _timelineFocus,
                                            builder: (context, child) =>
                                                DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          _timelineFocus
                                                              .hasFocus
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                          : Colors.transparent,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: child,
                                                ),
                                            child: Slider(
                                              focusNode: _timelineFocus,
                                              value: position,
                                              max: duration,
                                              semanticFormatterCallback:
                                                  (value) => _time(
                                                    Duration(
                                                      milliseconds: value
                                                          .round(),
                                                    ),
                                                  ),
                                              onChanged: (value) {
                                                if (!_busy) {
                                                  setState(
                                                    () => _seekPreview = value,
                                                  );
                                                }
                                              },
                                              onChangeEnd: _seek,
                                            ),
                                          ),
                                        ),
                                        Text(_time(value.duration)),
                                      ],
                                    ),
                                  if (ready && _busy)
                                    const LinearProgressIndicator(),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _ControlButton(
                                        label: 'Volver',
                                        icon: Icons.arrow_back,
                                        autofocus: true,
                                        onPressed: () =>
                                            Navigator.of(context).maybePop(),
                                      ),
                                      if (ready || _interrupted)
                                        _ControlButton(
                                          label: playing
                                              ? 'Pausar'
                                              : 'Reproducir video',
                                          icon: playing
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          onPressed: _togglePlayback,
                                        ),
                                      if (failed)
                                        _ControlButton(
                                          label: 'Reintentar',
                                          icon: Icons.refresh_rounded,
                                          onPressed: _retryStartup,
                                        ),
                                      if (ready || failed)
                                        _ControlButton(
                                          label: 'Calidad',
                                          icon: Icons.high_quality_outlined,
                                          value: _mode == QualityMode.automatic
                                              ? (_source.isAdaptive
                                                    ? 'Auto'
                                                    : 'Auto · ${_source.qualityLabel}')
                                              : _source.qualityLabel,
                                          onPressed: _chooseQuality,
                                        ),
                                      if (ready) ...[
                                        _ControlButton(
                                          label: 'Audio',
                                          icon: Icons.audiotrack,
                                          onPressed: _chooseAudio,
                                        ),
                                        _ControlButton(
                                          label: 'Subtítulos',
                                          icon: Icons.closed_caption_outlined,
                                          value: _subtitle?.language,
                                          onPressed: _chooseSubtitles,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (ready && _playRejected)
                                    const Text(
                                      'Pulsa Reproducir video para iniciar.',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _time(Duration duration) {
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    return duration.inHours == 0
        ? '$minutes:$seconds'
        : '${duration.inHours}:$minutes:$seconds';
  }
}

class _BufferingStatus extends StatelessWidget {
  const _BufferingStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: StreamingPalette.glassDark,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: StreamingPalette.divider),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 17),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Choice<T> {
  const _Choice(
    this.value,
    this.label, {
    this.selected = false,
    this.enabled = true,
    this.detail,
  });

  final T value;
  final String label;
  final bool selected;
  final bool enabled;
  final String? detail;
}

class _ChoiceDialog<T> extends StatefulWidget {
  const _ChoiceDialog({
    required this.title,
    required this.choices,
    required this.initial,
  });

  final String title;
  final List<_Choice<T>> choices;
  final int initial;

  @override
  State<_ChoiceDialog<T>> createState() => _ChoiceDialogState<T>();
}

class _ChoiceDialogState<T> extends State<_ChoiceDialog<T>> {
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final hasDetails = widget.choices.any((choice) => choice.detail != null);
    final extent =
        28 + scale.scale(16) * 1.35 + (hasDetails ? scale.scale(12) * 2.8 : 0);
    final count = widget.choices.length + 1;
    final total = extent * count;
    final height = math.min(total, MediaQuery.sizeOf(context).height * .54);
    final initial = widget.initial < 0 ? count - 1 : widget.initial;
    final scroll = _scroll ??= ScrollController(
      initialScrollOffset: math.min(extent * initial, total - height),
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: height,
        child: ListView.builder(
          controller: scroll,
          itemCount: count,
          itemExtent: extent,
          addAutomaticKeepAlives: false,
          itemBuilder: (context, index) {
            if (index == count - 1) {
              return _ControlButton(
                label: 'Cerrar',
                icon: Icons.close,
                autofocus: widget.initial < 0,
                onPressed: () => Navigator.of(context).pop(),
              );
            }
            final choice = widget.choices[index];
            final content = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(child: _ChoiceLabel(choice)),
                  if (choice.selected) const Icon(Icons.check),
                ],
              ),
            );
            return choice.enabled
                ? TvAction(
                    label: choice.label,
                    autofocus: index == widget.initial,
                    onPressed: () => Navigator.of(context).pop(choice.value),
                    child: SizedBox(height: extent, child: content),
                  )
                : content;
          },
        ),
      ),
    );
  }
}

class _ChoiceLabel extends StatelessWidget {
  const _ChoiceLabel(this.choice);

  final _Choice<Object?> choice;

  @override
  Widget build(BuildContext context) {
    final detail = choice.detail;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          choice.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: choice.enabled ? null : TextStyle(color: theme.disabledColor),
        ),
        if (detail != null)
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.value,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final String? value;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: TvAction(
        label: value == null ? label : '$label, $value',
        onPressed: onPressed,
        autofocus: autofocus,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: StreamingPalette.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon),
                if (value != null) ...[const SizedBox(width: 6), Text(value!)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
