// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../domain/contracts/subtitle_repository.dart';
import '../../domain/entities/iptv_channel.dart';
import '../../domain/entities/stream_option.dart';
import '../../domain/repositories/list_live_channels.dart';
import '../widgets/tv_action.dart';
import 'player_screen.dart';

final class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({
    required this.listChannels,
    required this.subtitles,
    super.key,
  });

  final ListLiveChannels listChannels;
  final SubtitleRepository subtitles;

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  late Future<LiveChannelPages> _channels = widget.listChannels();

  void _play(IptvChannel channel) {
    final source = StreamOption(
      quality: 'Auto',
      url: channel.url,
      providerId: 'iptv',
      deliveryHint: channel.isHls ? StreamDelivery.hls : null,
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          title: channel.name,
          source: source,
          sources: [source],
          providerNames: const {'iptv': 'IPTV'},
          subtitles: widget.subtitles,
          isLive: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const TvBackButton(autofocus: true),
      title: const Text('TV en vivo'),
    ),
    body: SafeArea(
      child: FutureBuilder<LiveChannelPages>(
        future: _channels,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Cargando canales',
              ),
            );
          }
          final pages = snapshot.data;
          if (pages == null) {
            return Center(
              child: FilledButton(
                onPressed: () {
                  setState(() {
                    _channels = widget.listChannels();
                  });
                },
                child: const Text('Reintentar cargar canales'),
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _ChannelList(
                key: ObjectKey(pages),
                pages: pages,
                onPlay: _play,
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _ChannelList extends StatefulWidget {
  const _ChannelList({required this.pages, required this.onPlay, super.key});

  final LiveChannelPages pages;
  final ValueChanged<IptvChannel> onPlay;

  @override
  State<_ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<_ChannelList> {
  late final _channels = widget.pages.nextPage();
  final _pageStart = FocusNode(debugLabel: 'Primer canal de la página');
  int? _focusIndex;

  @override
  void dispose() {
    _pageStart.dispose();
    super.dispose();
  }

  void _loadMore() {
    setState(() {
      _focusIndex = _channels.length;
      _channels.addAll(widget.pages.nextPage());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pageStart.context == null) return;
      FocusTraversalPolicy.defaultTraversalRequestFocusCallback(_pageStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_channels.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Agrega una lista IPTV en Ajustes para ver sus canales.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _channels.length + (widget.pages.hasMore ? 1 : 0),
      addAutomaticKeepAlives: false,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _channels.length) {
          return OutlinedButton(
            onPressed: _loadMore,
            child: const Text('Cargar más canales'),
          );
        }
        final channel = _channels[index];
        final colors = Theme.of(context).colorScheme;
        return TvAction(
          key: ValueKey(channel.url),
          label: 'Reproducir ${channel.name}',
          focusNode: index == _focusIndex ? _pageStart : null,
          onPressed: () => widget.onPlay(channel),
          child: ColoredBox(
            color: colors.surfaceContainerHigh,
            child: ListTile(
              leading: Icon(Icons.live_tv_outlined, color: colors.primary),
              title: Text(channel.name),
              subtitle: channel.group == null ? null : Text(channel.group!),
              trailing: const Icon(Icons.play_arrow_rounded),
            ),
          ),
        );
      },
    );
  }
}
