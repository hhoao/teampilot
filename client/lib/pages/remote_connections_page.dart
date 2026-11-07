import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../cubits/home_connection_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../services/storage/home_connect_attempt.dart';
import 'ssh_profiles/ssh_profiles_section.dart';

class RemoteConnectionsPage extends StatefulWidget {
  const RemoteConnectionsPage({super.key, this.embedded = false});

  /// When true, omits the [Scaffold] so the surrounding shell supplies chrome.
  final bool embedded;

  @override
  State<RemoteConnectionsPage> createState() => _RemoteConnectionsPageState();
}

class _RemoteConnectionsPageState extends State<RemoteConnectionsPage> {
  final _targetListKey = GlobalKey();

  /// Reads the home connection state when a [HomeConnectionCubit] provider is
  /// present, or `null` when it is not (e.g. before the shell wires it).
  HomeConnectionState? _readHomeConnection(BuildContext context) {
    try {
      return context.watch<HomeConnectionCubit>().state;
    } on Object {
      return null;
    }
  }

  void _scrollToTargetList() {
    final targetContext = _targetListKey.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final homeConn = _readHomeConnection(context);
    final showStatus =
        homeConn != null &&
        (homeConn.status == HomeConnectionStatus.unreachable ||
            homeConn.status == HomeConnectionStatus.reconnecting);
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStatus)
            _ConnectionStatusCard(
              state: homeConn,
              onSwitchConnection: _scrollToTargetList,
            ),
          if (showStatus) const SizedBox(height: 12),
          SshProfilesSection(key: _targetListKey, showRemoteConfig: false),
        ],
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(body: body);
  }
}

/// Status card shown while the SSH home is unreachable or retrying.
class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({
    required this.state,
    required this.onSwitchConnection,
  });

  final HomeConnectionState state;
  final VoidCallback onSwitchConnection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = state.host;
    final port = state.port ?? 22;
    final errorKind = state.lastErrorKind;
    return TpCard.outlined(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (host != null)
              Text(
                l10n.homeConnectionUnreachable(host, port),
                style: TpTextStyles.of(context).mdBoldTightSnug,
              ),
            if (state.status == HomeConnectionStatus.reconnecting) ...[
              const SizedBox(height: 4),
              Text(
                l10n.homeConnectionRetrying(state.attempt),
                style: TpTextStyles.of(context).mutedSm,
              ),
            ],
            if (errorKind != null) ...[
              const SizedBox(height: 4),
              Text(
                _errorKindLabel(l10n, errorKind),
                style: TpTextStyles.of(context).mutedSm,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state.canCancelRetry)
                  OutlinedButton(
                    onPressed: () =>
                        context.read<HomeConnectionCubit>().cancelRetry(),
                    child: Text(l10n.homeConnectionCancelRetry),
                  ),
                if (state.canRetryNow)
                  FilledButton(
                    onPressed: () =>
                        context.read<HomeConnectionCubit>().retryNow(),
                    child: Text(l10n.homeConnectionRetryNow),
                  ),
                OutlinedButton(
                  onPressed: onSwitchConnection,
                  child: Text(l10n.homeConnectionSwitch),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _errorKindLabel(AppLocalizations l10n, HomeErrorKind kind) {
    return switch (kind) {
      HomeErrorKind.tcpUnreachable => l10n.homeConnectionErrorTcp,
      HomeErrorKind.sshTimeout => l10n.homeConnectionErrorTimeout,
      HomeErrorKind.authFailed => l10n.homeConnectionErrorAuth,
      HomeErrorKind.transportError => l10n.homeConnectionErrorTransport,
      HomeErrorKind.unknown => l10n.homeConnectionErrorUnknown,
    };
  }
}
