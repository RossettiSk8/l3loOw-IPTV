final class SubtitleTrack {
  const SubtitleTrack({required this.url, required this.language, this.label});

  final Uri url;
  final String language;
  final String? label;
}
