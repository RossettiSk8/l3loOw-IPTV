import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/contracts/addon_repository.dart';
import '../../domain/entities/addon_entity.dart';
import '../../domain/repositories/addon_priority.dart';

final class LocalAddonRepository implements AddonRepository {
  LocalAddonRepository(
    this._preferences, {
    required Iterable<AddonEntity> defaults,
  }) : _defaults = defaults.toList()..sort(compareAddonPriority);

  static const _storageKey = 'addons.settings.v1';
  final SharedPreferencesAsync _preferences;
  final List<AddonEntity> _defaults;
  Future<void> _pending = Future.value();

  @override
  Future<List<AddonEntity>> list() async {
    await _pending;
    return List.unmodifiable(await _read());
  }

  @override
  Future<void> setEnabled(String id, bool enabled) {
    return _update(id, (addons, index) {
      addons[index] = addons[index].copyWith(isEnabled: enabled);
    });
  }

  @override
  Future<void> move(String id, AddonMove direction) {
    return _update(id, (addons, index) {
      final target = index + (direction == AddonMove.up ? -1 : 1);
      if (target >= 0 && target < addons.length) {
        addons.insert(target, addons.removeAt(index));
      }
    });
  }

  Future<void> _update(
    String id,
    void Function(List<AddonEntity>, int) change,
  ) {
    final operation = _pending.then((_) async {
      final addons = await _read();
      final index = addons.indexWhere((addon) => addon.id == id);
      if (index == -1) throw ArgumentError.value(id, 'id');
      change(addons, index);
      await _preferences.setString(
        _storageKey,
        jsonEncode([
          for (final addon in addons)
            {'id': addon.id, 'enabled': addon.isEnabled},
        ]),
      );
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<List<AddonEntity>> _read() async {
    final raw = await _preferences.getString(_storageKey);
    final saved = raw == null ? const [] : jsonDecode(raw);
    if (saved is! List) {
      throw const FormatException(
        'La configuración de complementos es inválida.',
      );
    }

    final available = {for (final addon in _defaults) addon.id: addon};
    final ordered = <AddonEntity>[];
    for (final row in saved) {
      if (row case {'id': final String id, 'enabled': final bool enabled}) {
        final addon = available.remove(id);
        if (addon != null) ordered.add(addon.copyWith(isEnabled: enabled));
      }
    }
    ordered.addAll(available.values);
    return [
      for (var index = 0; index < ordered.length; index++)
        ordered[index].copyWith(priority: index + 1),
    ];
  }
}
