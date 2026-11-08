import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../models/ssh_profile.dart';
import '../app/connection_mode_service.dart';
import '../termux/termux_transport_profile.dart';

/// Current SSH/Termux profile for the remote work plane, or null locally.
SshProfile? remoteSshProfileFromContext(BuildContext context) {
  final mode = context.read<ConnectionModeService>();
  if (!mode.isRemoteWorkPlane) return null;
  if (mode.isTermuxMode) {
    final config = context.read<TermuxCubit>().state.config;
    return config == null ? null : termuxTransportProfile(config);
  }
  return context.read<SshProfileCubit>().state.selectedProfile;
}
