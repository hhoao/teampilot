import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/ssh_profile.dart';
import '../services/connection_mode_service.dart';

/// Android app-bar control: shows the active SSH server and switches profiles.
class AndroidSshProfileSelector extends StatelessWidget {
  const AndroidSshProfileSelector({super.key});

  static const _manageProfilesValue = '__manage_ssh_profiles__';

  @override
  Widget build(BuildContext context) {
    context.watch<SessionPreferencesCubit>();
    final mode = context.read<ConnectionModeService>();
    if (!mode.isSshMode) {
      return const SizedBox.shrink();
    }

    final sshState = context.watch<SshProfileCubit>().state;
    if (sshState.isLoading || sshState.profiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final selected = sshState.selectedProfile ?? sshState.profiles.first;
    final l10n = context.l10n;

    return PopupMenuButton<String>(
      tooltip: l10n.sshProfileSelectorTooltip,
      onSelected: (value) {
        if (value == _manageProfilesValue) {
          context.go('/config/ssh-profiles');
          return;
        }
        context.read<SshProfileCubit>().selectProfile(value);
      },
      itemBuilder: (context) => [
        ...sshState.profiles.map(
          (profile) => _profileMenuItem(profile, selected.id),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _manageProfilesValue,
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.sshProfileSelectorManage)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 20),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _profileMenuItem(SshProfile profile, String selectedId) {
    final selected = profile.id == selectedId;
    return PopupMenuItem(
      value: profile.id,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name),
                Text(
                  profile.hostIdentifier,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (selected) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }
}
