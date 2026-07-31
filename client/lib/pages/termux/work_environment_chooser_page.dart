import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../ssh_profiles_page.dart';
import 'termux_setup_page.dart';

/// Android cold-start picker: on-device Termux or remote SSH home.
class WorkEnvironmentChooserPage extends StatelessWidget {
  const WorkEnvironmentChooserPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = TpTheme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose work environment')),
      body: ListView(
        padding: EdgeInsets.all(tp.spacing.lg),
        children: [
          Text(
            'Where should TeamPilot run your workspaces, shell, and agents?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tp.spacing.lg),
          _EnvironmentTile(
            title: 'On-device · Termux',
            subtitle:
                'Use Termux on this phone as your Linux work plane via local SSH.',
            icon: Icons.phone_android_outlined,
            iconColor: scheme.primary,
            onTap: () => _pushWithGateProviders(
              context,
              const TermuxSetupPage(),
            ),
          ),
          SizedBox(height: tp.spacing.md),
          _EnvironmentTile(
            title: 'Remote · SSH',
            subtitle: 'Connect to a remote Linux or macOS host over SSH.',
            icon: Icons.cloud_outlined,
            iconColor: scheme.tertiary,
            onTap: () => _pushWithGateProviders(
              context,
              const SshProfilesPage(),
            ),
          ),
        ],
      ),
    );
  }
}

void _pushWithGateProviders(BuildContext context, Widget page) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ConnectionModeService>.value(
            value: context.read<ConnectionModeService>(),
          ),
          RepositoryProvider<SshCredentialStore>.value(
            value: context.read<SshCredentialStore>(),
          ),
          RepositoryProvider<TerminalTransportFactory>.value(
            value: context.read<TerminalTransportFactory>(),
          ),
          RepositoryProvider<SshProfileRepository>.value(
            value: context.read<SshProfileRepository>(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SshProfileCubit>.value(
              value: context.read<SshProfileCubit>(),
            ),
            BlocProvider<SshConnectionCubit>.value(
              value: context.read<SshConnectionCubit>(),
            ),
            BlocProvider<SessionPreferencesCubit>.value(
              value: context.read<SessionPreferencesCubit>(),
            ),
            BlocProvider<TermuxCubit>.value(
              value: context.read<TermuxCubit>(),
            ),
          ],
          child: page,
        ),
      ),
    ),
  );
}

class _EnvironmentTile extends StatelessWidget {
  const _EnvironmentTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tp = TpTheme.of(context);

    return TpCard.outlined(
      child: TpHoverRow(
        onTap: onTap,
        padding: EdgeInsets.all(tp.spacing.md),
        trailing: Icon(Icons.chevron_right, color: iconColor),
        child: Row(
          children: [
            Icon(icon, size: 32, color: iconColor),
            SizedBox(width: tp.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  SizedBox(height: tp.spacing.xs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
