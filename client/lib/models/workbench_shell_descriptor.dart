import 'package:flutter/foundation.dart';

import 'workspace_terminal_session_spec.dart';

/// Everything needed to re-open a floating shell tab after an app restart.
@immutable
class WorkbenchShellDescriptor {
  const WorkbenchShellDescriptor({required this.cwd, required this.spec});

  final String cwd;
  final WorkspaceTerminalSessionSpec spec;

  Map<String, Object?> toJson() => {
    'cwd': cwd,
    'spec': workspaceTerminalSpecToJson(spec),
  };

  static WorkbenchShellDescriptor? fromJson(Object? json) {
    if (json is! Map) return null;
    final cwd = json['cwd'];
    final spec = workspaceTerminalSpecFromJson(json['spec']);
    if (cwd is! String || spec == null) return null;
    return WorkbenchShellDescriptor(cwd: cwd, spec: spec);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkbenchShellDescriptor &&
          cwd == other.cwd &&
          spec == other.spec;

  @override
  int get hashCode => Object.hash(cwd, spec);
}
