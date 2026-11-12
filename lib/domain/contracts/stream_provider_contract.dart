import '../entities/addon_entity.dart';
import '../entities/stream_option.dart';
import '../entities/stream_request.dart';

abstract interface class StreamProviderContract {
  /// Devuelve una lista vacía si el complemento no tiene opciones para la
  /// solicitud. Los fallos operativos se comunican mediante [Exception].
  Future<List<StreamOption>> getStreams(
    StreamRequest request,
    AddonEntity addon,
  );
}
