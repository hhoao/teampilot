import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../services/app/connection_mode_service.dart';
import 'menu/sidebar_action_menu.dart';

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

    return SidebarActionMenuIconAnchor(
      minWidth: 260,
      triggerBuilder: (context, controller) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
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
      },
      buildMenuChildren: (context, controller) {
        final specs = <SidebarActionMenuSpec>[
          for (final profile in sshState.profiles)
            SidebarActionMenuSpec.item(
              value: profile.id,
              icon: Icons.dns_outlined,
              label: profile.name,
              subtitle: Text(
                profile.hostIdentifier,
                style: AppTextStyles.of(context).bodySmall,
              ),
              selected: profile.id == selected.id,
            ),
          const SidebarActionMenuSpec.divider(),
          SidebarActionMenuSpec.item(
            value: _manageProfilesValue,
            icon: Icons.settings_outlined,
            label: l10n.sshProfileSelectorManage,
          ),
        ];
        return buildSidebarActionMenuChildren(
          context: context,
          specs: specs,
          menuController: controller,
          onSelect: (value) {
            if (value == _manageProfilesValue) {
              context.go('/config/ssh-profiles');
              return;
            }
            if (value is String) {
              context.read<SshProfileCubit>().selectProfile(value);
            }
          },
        );
      },
    );
  }
}
