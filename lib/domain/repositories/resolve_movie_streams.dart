import '../contracts/stream_resolver.dart';
import '../entities/media_item.dart';
import '../entities/stream_chain_result.dart';
import '../entities/stream_request.dart';

final class ResolveMovieStreams {
  const ResolveMovieStreams(this._resolver);

  final StreamResolver _resolver;

  Future<StreamChainResult> call(MediaItem movie) =>
      _resolver.resolve(StreamRequest.movie(movie));

  Future<StreamChainResult> preferred(MediaItem movie) =>
      _resolver.resolvePreferred(StreamRequest.movie(movie));

  Future<StreamChainResult> developerSources(MediaItem movie) => _resolver
      .resolve(StreamRequest.movie(movie), addonIds: const {'torrentio'});
}
