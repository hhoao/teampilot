import 'package:equatable/equatable.dart';
import 'install_job_scope.dart';

enum InstallJobKind {
  cliExecutable,
  toolchain,
  packAcquire,
  hubClone,
  fileTreeImport,
  appUpdate,
}

final class InstallJobKey extends Equatable {
  const InstallJobKey({
    required this.kind,
    required this.target,
    this.scope = const InstallJobScopeLocal(),
  });

  final InstallJobKind kind;
  final String target;
  final InstallJobScope scope;

  String get activityId =>
      'install-${kind.name}-$target-${scope.id}';

  @override
  List<Object?> get props => [kind, target, scope];
}
