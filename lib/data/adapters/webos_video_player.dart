import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_webos/video_player_webos.dart';

final class WebOsVideoPlayer extends VideoPlayerWebOs {
  static void configure() {
    final platform = VideoPlayerPlatform.instance;
    if (platform is VideoPlayerWebOs && platform is! WebOsVideoPlayer) {
      VideoPlayerPlatform.instance = WebOsVideoPlayer();
    }
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    // video_player aplica 1.0 al inicializar. LG controla el volumen por sistema.
    if (volume != 1.0) await super.setVolume(textureId, volume);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    // LG no expone mezcla de audio, por lo que el valor por defecto no necesita un mensaje.
    if (mixWithOthers) await super.setMixWithOthers(mixWithOthers);
  }
}
