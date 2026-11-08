import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../app/connection_mode_service.dart';
import '../storage/home_target_controller.dart';
import '../termux/termux_transport_profile.dart';

/// Current SSH/Termux profile for the remote work plane, or null locally.
///
/// Prefer the active home target over [SshProfileCubit.selectedProfile]: the
/// Android app bar can switch the home profile independently, and the settings
/// card must probe the machine the user is actually connected to.
SshProfile? remoteSshProfileFromContext(BuildContext context) {
  final mode = context.read<ConnectionModeService>();
  if (!mode.isRemoteWorkPlane) return null;
  if (mode.isTermuxMode) {
    final config = context.read<TermuxCubit>().state.config;
    return config == null ? null : termuxTransportProfile(config);
  }
  final profiles = context.read<SshProfileCubit>().state.profiles;
  try {
    final home = context.read<HomeTargetController>().current;
    final homeProfileId = home.sshProfileId ?? sshProfileIdOfId(home.id);
    if (homeProfileId != null && homeProfileId.isNotEmpty) {
      for (final profile in profiles) {
        if (profile.id == homeProfileId) return profile;
      }
    }
  } on Object {
    // Hosts without the controller (tests / standalone cards) fall back to
    // the profile cubit's selection.
  }
  return context.read<SshProfileCubit>().state.selectedProfile;
}
