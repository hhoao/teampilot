import 'package:flutter/foundation.dart';

/// Stable identity of one home storage plane.
///
/// Two runtimes with the same identity may rebind transport to each other;
/// any difference (including only [appDataRoot]) means a different plane that
/// must be constructed and disposed independently.
@immutable
final class HomeRuntimeIdentity {
  const HomeRuntimeIdentity({
    required this.targetId,
    required this.appDataRoot,
  });

  /// `'local'`, `'ssh:<profileId>'`, `'wsl:<distro>'`, `'termux:default'`.
  final String targetId;

  /// Resolved `<teampilotRoot>` on the host that owns [targetId].
  final String appDataRoot;

  @override
  bool operator ==(Object other) =>
      other is HomeRuntimeIdentity &&
      other.targetId == targetId &&
      other.appDataRoot == appDataRoot;

  @override
  int get hashCode => Object.hash(targetId, appDataRoot);

  @override
  String toString() => '$targetId\u0000$appDataRoot';
}
