import '../../models/runtime_target.dart';
import 'runtime_target_registry.dart';

/// UI-facing handle for choosing the home target. Wraps the device-local home
/// authority + the target catalogs + the bootstrap switch side-effect chain so
/// the picker stays free of app-shell wiring.
///
/// There are two independent SSH catalogs with distinct semantics:
///  * [registry] is the device-local home-binding palette (A source, 远程连接页).
///    A connection here becomes the home plane. Used by the home-target picker.
///  * [workloadRegistry] is the home-plane workload host catalog (B source, SSH
///    服务器页) persisted in `targets.json`. Used by every workspace machine
///    picker. It is optional so tests / embedded harnesses that build a single
///    registry keep working; in that case workspace enumeration falls back to
///    the home palette.
class HomeTargetController {
  HomeTargetController({
    required RuntimeTargetRegistry registry,
    RuntimeTargetRegistry? workloadRegistry,
    required RuntimeTarget Function() current,
    required Future<void> Function(String id) switchTo,
  }) : _registry = registry,
       _workloadRegistry = workloadRegistry,
       _current = current,
       _switchTo = switchTo;

  final RuntimeTargetRegistry _registry;
  final RuntimeTargetRegistry? _workloadRegistry;
  final RuntimeTarget Function() _current;
  final Future<void> Function(String id) _switchTo;

  /// Active home target (local / SSH / WSL).
  RuntimeTarget get current => _current();

  /// Canonical id of the active home target.
  String get currentId => _current().id;

  /// Selectable HOME targets (A source): device-local home-binding profiles,
  /// scoped to the platform by the caller. [wslDistro] is surfaced as the
  /// implicit `wsl:<distro>` option on Windows. Used only by the home-target
  /// picker — never by workspace machine lists.
  Future<List<RuntimeTarget>> listSelectable({String wslDistro = ''}) =>
      _registry.listTargets(wslDistro: wslDistro);

  /// Workspace / mixed-workspace machine targets (B source): home-plane
  /// workload hosts from `targets.json`. Used by every workspace machine
  /// picker and the directory picker. Falls back to the home palette only when
  /// no workload registry is wired (tests / embedded harnesses).
  Future<List<RuntimeTarget>> listWorkspaceTargets({String wslDistro = ''}) =>
      (_workloadRegistry ?? _registry).listTargets(wslDistro: wslDistro);

  /// Persist + rebind the home target, then reinstall + reload app data.
  /// Same-target select is a no-op: Android Connect auto-selects the profile it
  /// just connected as home; re-selecting it must not evict the live context.
  Future<void> select(String id) {
    if (currentId == id) return Future.value();
    return _switchTo(id);
  }
}
