import '../../models/runtime_target.dart';
import 'runtime_target_registry.dart';

/// UI-facing handle for choosing the home target. Wraps the device-local home
/// authority + the target catalog + the bootstrap switch side-effect chain so
/// the picker stays free of app-shell wiring.
class HomeTargetController {
  HomeTargetController({
    required RuntimeTargetRegistry registry,
    required RuntimeTarget Function() current,
    required Future<void> Function(String id) switchTo,
  }) : _registry = registry,
       _current = current,
       _switchTo = switchTo;

  final RuntimeTargetRegistry _registry;
  final RuntimeTarget Function() _current;
  final Future<void> Function(String id) _switchTo;

  /// Canonical id of the active home target.
  String get currentId => _current().id;

  /// Selectable targets, scoped to the platform by the caller. [wslDistro] is
  /// surfaced as the implicit `wsl:<distro>` option on Windows.
  Future<List<RuntimeTarget>> listSelectable({String wslDistro = ''}) =>
      _registry.listTargets(wslDistro: wslDistro);

  /// Persist + rebind the home target, then reinstall + reload app data.
  Future<void> select(String id) => _switchTo(id);
}
