import 'stream_option.dart';

final class StreamProviderFailure {
  const StreamProviderFailure(this.addonId, this.error);

  final String addonId;
  final Exception error;
}

final class StreamChainResult {
  StreamChainResult({
    required Iterable<StreamOption> options,
    required Iterable<StreamProviderFailure> failures,
    Map<String, String> providerNames = const {},
    Iterable<StreamOption>? startupOptions,
  }) : options = List.unmodifiable(options),
       failures = List.unmodifiable(failures),
       providerNames = Map.unmodifiable(providerNames),
       _startupOptions = startupOptions == null
           ? null
           : List.unmodifiable(startupOptions);

  final List<StreamOption> options;
  final List<StreamOption>? _startupOptions;
  List<StreamOption> get startupOptions => _startupOptions ?? playableOptions;
  StreamOption? get preferredOption => startupOptions.firstOrNull;

  List<StreamOption> get playableOptions =>
      options.where((option) => option.isPlayable).toList(growable: false);
  final List<StreamProviderFailure> failures;
  final Map<String, String> providerNames;
}
