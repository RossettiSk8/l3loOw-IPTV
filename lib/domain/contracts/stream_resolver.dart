import '../entities/stream_chain_result.dart';
import '../entities/stream_request.dart';

abstract interface class StreamResolver {
  Future<StreamChainResult> resolve(
    StreamRequest request, {
    Set<String>? addonIds,
  });

  Future<StreamChainResult> resolvePreferred(StreamRequest request);
}
