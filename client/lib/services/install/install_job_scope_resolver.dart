import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../models/install_job/install_job_scope.dart';
import '../../models/ssh_profile.dart';
import '../app/connection_mode_service.dart';
import '../termux/termux_transport_profile.dart';

InstallJobScope installJobScopeForProfile(SshProfile? profile) {
  if (profile == null) return const InstallJobScopeLocal();
  return InstallJobScopeSsh(profile.id);
}

InstallJobScope installJobScopeForContext(BuildContext context) {
  final mode = context.read<ConnectionModeService>();
  if (!mode.isRemoteWorkPlane) return const InstallJobScopeLocal();
  return installJobScopeForProfile(_remoteSshProfile(context, mode));
}

SshProfile? remoteSshProfileForContext(
  BuildContext context,
  ConnectionModeService mode,
) => _remoteSshProfile(context, mode);

SshProfile? _remoteSshProfile(
  BuildContext context,
  ConnectionModeService mode,
) {
  if (!mode.isRemoteWorkPlane) return null;
  if (mode.isTermuxMode) {
    final config = context.read<TermuxCubit>().state.config;
    return config == null ? null : termuxTransportProfile(config);
  }
  return context.read<SshProfileCubit>().state.selectedProfile;
}
