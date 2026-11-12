import '../entities/subtitle_track.dart';

abstract interface class SubtitleRepository {
  Future<String> read(SubtitleTrack track);
}
