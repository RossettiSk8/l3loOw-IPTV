final class AddonEntity {
  const AddonEntity({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.isEnabled,
    required this.priority,
  });

  final String id;
  final String name;
  final Uri baseUrl;
  final bool isEnabled;

  /// Los números menores se consultan primero.
  final int priority;

  AddonEntity copyWith({bool? isEnabled, int? priority}) => AddonEntity(
    id: id,
    name: name,
    baseUrl: baseUrl,
    isEnabled: isEnabled ?? this.isEnabled,
    priority: priority ?? this.priority,
  );
}
