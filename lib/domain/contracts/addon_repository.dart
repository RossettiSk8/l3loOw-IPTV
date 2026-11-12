import '../entities/addon_entity.dart';

abstract interface class AddonRepository {
  /// Devuelve la configuración vigente en orden de prioridad.
  Future<List<AddonEntity>> list();

  Future<void> setEnabled(String id, bool enabled);

  /// Mueve el complemento una posición dentro de la lista.
  Future<void> move(String id, AddonMove direction);
}

enum AddonMove { up, down }
