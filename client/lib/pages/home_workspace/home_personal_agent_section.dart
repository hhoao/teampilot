import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../models/personal_profile.dart';
import 'workspace/config/workspace_agent_section.dart' show WorkspaceAgentConfigForm;

/// Personal identity agent + CLI preset defaults on the home workspace.
class HomePersonalAgentSection extends StatelessWidget {
  const HomePersonalAgentSection({required this.profileId, super.key});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final identityCubit = context.watch<LaunchProfileCubit>();
    final personal = identityCubit.byId(profileId);
    if (personal is! PersonalProfile) {
      return const Center(child: CircularProgressIndicator());
    }
    return WorkspaceAgentConfigForm(
      key: ValueKey(personal.id),
      personal: personal,
      cubit: context.read<LaunchProfileCubit>(),
    );
  }
}
