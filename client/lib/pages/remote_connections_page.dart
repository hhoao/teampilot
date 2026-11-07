import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../cubits/home_connection_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../services/storage/home_connect_attempt.dart';
import 'remote_targets_page.dart';
import 'ssh_profiles/ssh_profiles_section.dart';

class RemoteConnectionsPage extends StatefulWidget {
  const RemoteConnectionsPage({super.key, this.embedded = false});

  /// When true, omits the [Scaffold] so the surrounding shell supplies chrome.
  final bool embedded;

  @override
  State<RemoteConnectionsPage> createState() => _RemoteConnectionsPageState();
}

class _RemoteConnectionsPageState extends State<RemoteConnectionsPage> {
  /// Reads the home connection state when a [HomeConnectionCubit] provider is
  /// present, or `null` when it is not (e.g. before the shell wires it).
  HomeConnectionState? _readHomeConnection(BuildContext context) {
    try {
      return context.watch<HomeConnectionCubit>().state;
    } on Object {
      return null;
    }
  }

  void _openTargetsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RemoteTargetsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final homeConn = _readHomeConnection(context);
    final showStatus =
        homeConn != null &&
        (homeConn.status == HomeConnectionStatus.unreachable ||
            homeConn.status == HomeConnectionStatus.reconnecting);

    // Status view: a single centered card. The target list lives on its own
    // page, reached through 「切换连接」.
    if (showStatus) {
      final statusColumn = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConnectionStatusCard(
            state: homeConn,
            onSwitchConnection: () => _openTargetsPage(context),
          ),
        ],
      );
      if (widget.embedded) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: statusColumn,
        );
      }
      return Scaffold(
        // SafeArea keeps the card clear of the status bar; the viewport-tall
        // minimum lets `mainAxisAlignment` center it while still scrolling
        // when the card is taller than the screen.
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minHeight = constraints.maxHeight.isFinite
                  ? (constraints.maxHeight - 32).clamp(0.0, double.infinity)
                  : 0.0;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: statusColumn,
                ),
              );
            },
          ),
        ),
      );
    }

    // Setup / settings view: the target list.
    const list = SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: SshProfilesSection(showRemoteConfig: false),
    );
    if (widget.embedded) return list;
    return Scaffold(body: SafeArea(child: list));
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (host != null)
              Text(
                l10n.homeConnectionUnreachable(host, port),
                textAlign: TextAlign.center,
                style: TpTextStyles.of(context).mdBoldTightSnug,
              ),
            if (state.status == HomeConnectionStatus.reconnecting) ...[
              const SizedBox(height: 4),
              Text(
                l10n.homeConnectionRetrying(state.attempt),
                textAlign: TextAlign.center,
                style: TpTextStyles.of(context).mutedSm,
              ),
            ],
            if (errorKind != null) ...[
              const SizedBox(height: 4),
              Text(
                _errorKindLabel(l10n, errorKind),
                textAlign: TextAlign.center,
                style: TpTextStyles.of(context).mutedSm,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // One toggle button: stop while auto-retrying, resume while
                // stopped — never two mutually-useless actions at once.
                if (state.canCancelRetry)
                  OutlinedButton(
                    onPressed: () =>
                        context.read<HomeConnectionCubit>().cancelRetry(),
                    child: Text(l10n.homeConnectionCancelRetry),
                  )
                else if (state.canRetryNow)
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
      HomeErrorKind.hostIdentityChanged => l10n.homeConnectionErrorHostKey,
      HomeErrorKind.transportError => l10n.homeConnectionErrorTransport,
      HomeErrorKind.unknown => l10n.homeConnectionErrorUnknown,
    };
  }
}
