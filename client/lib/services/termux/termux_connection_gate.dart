import '../../models/runtime_target.dart';

/// Whether work-plane operations may proceed for the current Termux home/target.
bool allowTermuxWorkOps({required bool isTermuxHome, required bool connected}) =>
    !isTermuxHome || connected;

bool isTermuxWorkOpsBlocked({
  required bool isTermuxHome,
  required bool connected,
}) =>
    !allowTermuxWorkOps(isTermuxHome: isTermuxHome, connected: connected);

/// Returns [message] when [target] or [home] is on the Termux plane but
/// Termux is disconnected; otherwise null.
String? termuxWorkOpsBlockMessage({
  required RuntimeTarget target,
  required RuntimeTarget home,
  required bool termuxConnected,
  required String message,
}) {
  final onTermuxPlane =
      target.kind == RuntimeKind.termux || home.kind == RuntimeKind.termux;
  if (isTermuxWorkOpsBlocked(
    isTermuxHome: onTermuxPlane,
    connected: termuxConnected,
  )) {
    return message;
  }
  return null;
}
