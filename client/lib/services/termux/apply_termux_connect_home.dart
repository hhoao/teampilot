import '../../models/runtime_target.dart';

/// Termux Connect side-effect: switch home to the on-device Termux work plane.
Future<void> applyTermuxConnectHome({
  required Future<void> Function(String homeId) selectHome,
}) =>
    selectHome(RuntimeTarget.termuxDefaultId);

/// Clear-setup side-effect: return home to unbound local so StartupGate reopens.
Future<void> applyTermuxClearSetupHome({
  required Future<void> Function(String homeId) selectHome,
}) =>
    selectHome(RuntimeTarget.localId);
