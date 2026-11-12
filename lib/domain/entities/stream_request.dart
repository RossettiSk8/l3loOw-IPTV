import 'media_item.dart';

final class StreamRequest {
  StreamRequest.movie(this.media) : season = null, episode = null {
    if (media.kind != MediaKind.movie) {
      throw ArgumentError('La solicitud requiere una película.');
    }
  }

  StreamRequest.episode(this.media, {required int season, required int episode})
    : season = season,
      episode = episode {
    if (media.kind != MediaKind.series || season < 0 || episode < 1) {
      throw ArgumentError(
        'La solicitud requiere una temporada y un episodio válidos.',
      );
    }
  }

  final MediaItem media;
  final int? season;
  final int? episode;
}
