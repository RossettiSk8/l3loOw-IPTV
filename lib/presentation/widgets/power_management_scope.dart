import 'package:flutter/widgets.dart';

import '../../core/dependencies/power_management_service.dart';

final class PowerManagementScope extends InheritedWidget {
  const PowerManagementScope({
    required this.service,
    required super.child,
    super.key,
  });

  final PowerManagementService service;

  static PowerManagementService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PowerManagementScope>()
      ?.service;

  @override
  bool updateShouldNotify(PowerManagementScope oldWidget) =>
      oldWidget.service != service;
}
