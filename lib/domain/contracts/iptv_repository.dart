import '../entities/iptv_playlist.dart';

abstract interface class IptvRepository {
  Future<List<IptvPlaylist>> list();

  Future<void> addPlaylist(String address);

  Future<void> removePlaylist(Uri url);

  /// Devuelve el número de entradas eliminadas de las listas guardadas.
  Future<int> purgeBrokenLinks();
}
