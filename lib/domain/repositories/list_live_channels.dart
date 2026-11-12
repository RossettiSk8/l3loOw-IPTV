import '../contracts/iptv_repository.dart';
import '../entities/iptv_channel.dart';
import '../entities/iptv_playlist.dart';

final class ListLiveChannels {
  const ListLiveChannels(this._repository);

  final IptvRepository _repository;

  Future<LiveChannelPages> call() async =>
      LiveChannelPages(_distinct(await _repository.list()).iterator);

  Iterable<IptvChannel> _distinct(List<IptvPlaylist> playlists) sync* {
    final seen = <Uri>{};
    for (final playlist in playlists) {
      for (final channel in playlist.channels) {
        if (seen.add(channel.url)) yield channel;
      }
    }
  }
}

final class LiveChannelPages {
  LiveChannelPages(Iterator<IptvChannel> iterator)
    : _iterator = iterator.moveNext() ? iterator : null;

  Iterator<IptvChannel>? _iterator;

  bool get hasMore => _iterator != null;

  List<IptvChannel> nextPage({int pageSize = 100}) {
    if (pageSize < 1) throw ArgumentError.value(pageSize, 'pageSize');
    final iterator = _iterator;
    if (iterator == null) return const [];
    final items = <IptvChannel>[];
    while (items.length < pageSize) {
      items.add(iterator.current);
      if (!iterator.moveNext()) {
        _iterator = null;
        break;
      }
    }
    return items;
  }
}
