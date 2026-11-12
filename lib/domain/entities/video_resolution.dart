final _dimensions = RegExp(
  r'\b\d{3,5}\s*[x×]\s*(\d{3,4})\b',
  caseSensitive: false,
);
final _progressive = RegExp(r'\b(\d{3,4})\s*p\b', caseSensitive: false);
final _aliases = RegExp(r'\b(8k|4k|uhd|fhd|full\s+hd)\b', caseSensitive: false);

int? parseVideoHeight(Object? value, {bool allowBareHeight = false}) {
  if (value is num && value.isFinite && value == value.round()) {
    return _validHeight(value.toInt());
  }
  if (value is! String) return null;
  final text = value.trim();
  if (allowBareHeight) {
    final height = _validHeight(int.tryParse(text));
    if (height != null) return height;
  }
  final explicit =
      (_dimensions.firstMatch(text) ?? _progressive.firstMatch(text))?.group(1);
  if (explicit != null) return _validHeight(int.tryParse(explicit));
  return switch (_aliases.firstMatch(text)?.group(1)?.toLowerCase()) {
    '8k' => 4320,
    '4k' || 'uhd' => 2160,
    final String _ => 1080,
    null => null,
  };
}

int? _validHeight(int? height) =>
    height != null && height >= 144 && height <= 8640 ? height : null;

String formatVideoHeight(int height) => switch (height) {
  2160 => '4K',
  4320 => '8K',
  _ => '${height}p',
};
