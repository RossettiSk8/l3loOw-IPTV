import '../entities/addon_entity.dart';

/// Ordena por prioridad ascendente y desempata por ID.
int compareAddonPriority(AddonEntity left, AddonEntity right) {
  final priority = left.priority.compareTo(right.priority);
  return priority == 0 ? left.id.compareTo(right.id) : priority;
}
