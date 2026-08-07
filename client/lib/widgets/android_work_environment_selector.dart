import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/termux_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/runtime_target.dart';
import '../models/ssh_profile.dart';
import '../services/app/connection_mode_service.dart';
import '../services/storage/home_target_controller.dart';
import '../pages/termux/termux_setup_page.dart';

/// Android app-bar control: switch between Termux and remote SSH work homes.
class AndroidWorkEnvironmentSelector extends StatelessWidget {
  const AndroidWorkEnvironmentSelector({super.key});

  static const termuxValue = RuntimeTarget.termuxDefaultId;
  static const _manageSshProfilesValue = '__manage_ssh_profiles__';
  static const _manageTermuxSetupValue = '__manage_termux_setup__';

  @override
  Widget build(BuildContext context) {
    context.watch<SessionPreferencesCubit>();
    final mode = context.read<ConnectionModeService>();
    if (!mode.hasBoundAndroidWorkHome) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final homeController = context.read<HomeTargetController>();
    final termuxState = context.watch<TermuxCubit>().state;
    final sshState = context.watch<SshProfileCubit>().state;
    final showTermux = termuxState.isConfigured;

    final selectedId = homeController.currentId;
    final selectedLabel = _selectedLabel(
      l10n: l10n,
      selectedId: selectedId,
      sshProfiles: sshState.profiles,
      termuxUsername: termuxState.config?.username,
    );

    return TpActionMenuIconAnchor(
      minWidth: 280,
      triggerBuilder: (context, controller) {
        return TpHover(
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
                Icon(
                  mode.isTermuxMode
                      ? Icons.phone_android_outlined
                      : Icons.dns_outlined,
                  size: context.tpIconSizes.md,
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    selectedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTextStyles.of(context).mdSemiboldTightSnug,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
      buildMenuChildren: (context, controller) {
        final specs = <TpActionMenuSpec>[
          if (showTermux)
            TpActionMenuSpec.item(
              value: termuxValue,
              icon: Icons.phone_android_outlined,
              label: l10n.androidWorkEnvironmentSelectorTermux,
              subtitle: Text(
                termuxState.config?.username ?? l10n.termuxSetupUsernameHint,
                style: TpTextStyles.of(context).sm,
              ),
              selected: selectedId == termuxValue,
            ),
          for (final profile in sshState.profiles)
            TpActionMenuSpec.item(
              value: 'ssh:${profile.id}',
              icon: Icons.dns_outlined,
              label: profile.name,
              subtitle: Text(
                profile.hostIdentifier,
                style: TpTextStyles.of(context).sm,
              ),
              selected: selectedId == 'ssh:${profile.id}',
            ),
          const TpActionMenuSpec.divider(),
          if (showTermux)
            TpActionMenuSpec.item(
              value: _manageTermuxSetupValue,
              icon: Icons.settings_outlined,
              label: l10n.androidWorkEnvironmentSelectorManageTermux,
            ),
          TpActionMenuSpec.item(
            value: _manageSshProfilesValue,
            icon: Icons.settings_outlined,
            label: l10n.sshProfileSelectorManage,
          ),
        ];
        return buildTpActionMenuChildren(
          context: context,
          specs: specs,
          menuController: controller,
          onSelect: (value) => _onSelect(context, value),
        );
      },
    );
  }

  static String _selectedLabel({
    required dynamic l10n,
    required String selectedId,
    required List<SshProfile> sshProfiles,
    String? termuxUsername,
  }) {
    if (selectedId == termuxValue) {
      final user = termuxUsername?.trim() ?? '';
      if (user.isNotEmpty) {
        return l10n.androidWorkEnvironmentSelectorTermuxWithUser(user);
      }
      return l10n.androidWorkEnvironmentSelectorTermux;
    }
    final profileId = sshProfileIdOfId(selectedId);
    if (profileId != null) {
      for (final profile in sshProfiles) {
        if (profile.id == profileId) {
          return profile.name;
        }
      }
    }
    return l10n.androidWorkEnvironmentSelectorLabel;
  }

  Future<void> _onSelect(BuildContext context, Object? value) async {
    if (value == _manageSshProfilesValue) {
      context.go('/config/ssh-profiles');
      return;
    }
    if (value == _manageTermuxSetupValue) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const TermuxSetupPage(),
        ),
      );
      return;
    }
    if (value is! String) return;

    final homeController = context.read<HomeTargetController>();
    if (value == termuxValue) {
      await homeController.select(termuxValue);
      if (!context.mounted) return;
      await context.read<TermuxCubit>().connect();
      return;
    }
    if (value.startsWith('ssh:')) {
      homeController.select(value);
    }
  }
}
