import 'iptv_channel.dart';

final class IptvPlaylist {
  IptvPlaylist({required this.url, required Iterable<IptvChannel> channels})
    : channels = List.unmodifiable(channels);

  final Uri url;
  final List<IptvChannel> channels;
}
