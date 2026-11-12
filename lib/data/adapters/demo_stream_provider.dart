import '../../domain/contracts/stream_provider_contract.dart';
import '../../domain/entities/addon_entity.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/stream_option.dart';
import '../../domain/entities/stream_request.dart';

final class DemoStreamProvider implements StreamProviderContract {
  const DemoStreamProvider();

  // Archivos progresivos publicados por el canal Blender Open Movies.
  static const _files = {
    'demo-charge': [
      (
        quality: '1080p',
        file: '01d4421b-55f7-4349-bb6c-b8aa3053ffe4-1080.mp4',
        size: 100635721,
      ),
      (
        quality: '720p',
        file: '70528f27-fd51-479f-8146-abb5a7a81fff-720.mp4',
        size: 54603117,
      ),
    ],
    'demo-big-buck-bunny': [
      (
        quality: '720p',
        file: 'bf1f3fb5-b119-4f9f-9930-8e20e892b898-720.mp4',
        size: 110916740,
      ),
    ],
  };

  @override
  Future<List<StreamOption>> getStreams(
    StreamRequest request,
    AddonEntity addon,
  ) async {
    if (request.media.kind != MediaKind.movie) return const [];
    if (request.media.id == 'demo') {
      return [
        StreamOption(quality: 'Auto', url: addon.baseUrl, providerId: addon.id),
      ];
    }
    return [
      for (final source in _files[request.media.id] ?? const [])
        StreamOption(
          quality: source.quality,
          url: Uri.https(
            'video.blender.org',
            '/object-storage/web_videos/${source.file}',
          ),
          providerId: addon.id,
          size: source.size,
          variantGroup: request.media.id,
        ),
    ];
  }
}
