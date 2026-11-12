// El SDK de LG basado en Flutter 3.38 incluye Material en el framework.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'core/dependencies/app_dependencies.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/widgets/app_settings_provider.dart';
import 'presentation/widgets/ota_update_dialog.dart';
import 'presentation/widgets/power_management_scope.dart';
import 'presentation/widgets/streaming_theme.dart';

void main() {
  runApp(const AppStreaming());
}

class AppStreaming extends StatefulWidget {
  const AppStreaming({super.key});

  @override
  State<AppStreaming> createState() => _AppStreamingState();
}

class _AppStreamingState extends State<AppStreaming> {
  final _dependencies = AppDependencies.create();
  late final _settings = AppSettings(
    _dependencies.playbackPreferences,
    library: _dependencies.library,
  );

  @override
  void dispose() {
    _settings.dispose();
    _dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final updates = _dependencies.updates;
    return PowerManagementScope(
      service: _dependencies.power,
      child: AppSettingsProvider(
        settings: _settings,
        updates: updates,
        child: MaterialApp(
          title: 'l3loOw',
          debugShowCheckedModeBanner: false,
          theme: streamingTheme(),
          home: OtaStartupCheck(
            updates: updates,
            child: HomeScreen(
              mediaRepository: _dependencies.media,
              addonRepository: _dependencies.addons,
              iptvRepository: _dependencies.iptv,
              resolveMovieStreams: _dependencies.resolveMovieStreams,
              subtitles: _dependencies.subtitles,
            ),
          ),
        ),
      ),
    );
  }
}
