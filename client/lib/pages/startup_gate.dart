import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/home_connection_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../services/app/connection_mode_service.dart';
import 'remote_connections_page.dart';
import 'termux/work_environment_chooser_page.dart';

class StartupGate extends StatelessWidget {
  const StartupGate({super.key, required this.child, this.isAndroid});

  final Widget child;

  /// Test override; defaults to [Platform.isAndroid].
  final bool? isAndroid;

  @override
  Widget build(BuildContext context) {
    context.watch<SessionPreferencesCubit>();
    final mode = context.read<ConnectionModeService>();
    // Android needs a bound work home (Termux or SSH). Desktop local/wsl passes.
    final android = isAndroid ?? Platform.isAndroid;
    final androidNeedsWorkHome = android && !mode.hasBoundAndroidWorkHome;
    if (!mode.isRemoteWorkPlane && !androidNeedsWorkHome) return child;

    final sshState = context.watch<SshProfileCubit>().state;

    if (sshState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (mode.requiresSshProfileSetup) {
      return const RemoteConnectionsPage();
    }

    // Optional until the shell wires the provider: absence means "no status".
    final homeConn = _readHomeConnection(context);
    if (homeConn != null) {
      switch (homeConn.status) {
        case HomeConnectionStatus.unreachable:
        case HomeConnectionStatus.reconnecting:
          return const RemoteConnectionsPage();
        case HomeConnectionStatus.connecting:
          return _HomeConnectingPage(state: homeConn);
        case HomeConnectionStatus.connected:
          break;
      }
    }

    if (androidNeedsWorkHome) {
      return const WorkEnvironmentChooserPage();
    }

    return child;
  }

  /// Reads the home connection state when a [HomeConnectionCubit] provider is
  /// present, or `null` when it is not (e.g. before the shell wires it).
  static HomeConnectionState? _readHomeConnection(BuildContext context) {
    try {
      return context.watch<HomeConnectionCubit>().state;
    } on Object {
      return null;
    }
  }
}

/// Small progress page shown while a shell-triggered home retry runs.
class _HomeConnectingPage extends StatelessWidget {
  const _HomeConnectingPage({required this.state});

  final HomeConnectionState state;

  @override
  Widget build(BuildContext context) {
    final host = state.host;
    final target = host == null ? null : '$host:${state.port ?? 22}';
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.sshProfileStatusConnecting),
            if (target != null) ...[const SizedBox(height: 4), Text(target)],
          ],
        ),
      ),
    );
  }
}
