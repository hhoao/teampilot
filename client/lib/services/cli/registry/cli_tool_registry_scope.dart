import 'package:flutter/widgets.dart';

import 'cli_tool_registry.dart';

class CliToolRegistryScope extends InheritedWidget {
  const CliToolRegistryScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final CliToolRegistry registry;

  static CliToolRegistry of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CliToolRegistryScope>();
    assert(
      scope != null,
      'CliToolRegistryScope not found in widget tree',
    );
    return scope!.registry;
  }

  static CliToolRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CliToolRegistryScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(CliToolRegistryScope oldWidget) =>
      oldWidget.registry != registry;
}
