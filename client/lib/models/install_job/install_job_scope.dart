import 'package:equatable/equatable.dart';

sealed class InstallJobScope extends Equatable {
  const InstallJobScope();
  String get id;
}

final class InstallJobScopeLocal extends InstallJobScope {
  const InstallJobScopeLocal();
  @override
  String get id => 'local';
  @override
  List<Object?> get props => const [];
}

final class InstallJobScopeSsh extends InstallJobScope {
  const InstallJobScopeSsh(this.profileId);
  final String profileId;
  @override
  String get id => 'ssh-$profileId';
  @override
  List<Object?> get props => [profileId];
}
