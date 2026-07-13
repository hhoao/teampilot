import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/run_session.dart';
import '../../pages/workspace_shell/workspace_shell_tabs.dart';
import '../../services/run/run_platform.dart';
import '../../services/run/run_terminal_bridge.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import 'run_session_page.dart';

/// Bottom Run pages: one tab per [RunSession], text log via [RunTerminalBridge].
class RunPanel extends StatefulWidget {
  const RunPanel({this.bridge, super.key});

  /// Injected for tests; defaults to listening on [RunCubit] session output.
  final RunTerminalBridge? bridge;

  @override
  State<RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends State<RunPanel> {
  RunTerminalBridge? _ownedBridge;
  RunTerminalBridge? _bridge;
  bool _bridgeInitStarted = false;
  String? _activeSessionId;
  List<String> _seenSessionIds = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.bridge != null) {
      _bridge = widget.bridge;
      return;
    }
    if (_ownedBridge != null || _bridgeInitStarted) return;
    _bridgeInitStarted = true;
    unawaited(_bindOutputBridge());
  }

  Future<void> _bindOutputBridge() async {
    final cubit = context.read<RunCubit>();
    await whenRunPlatformReady(cubit.platform);
    if (!mounted || _ownedBridge != null) return;

    final manager = cubit.platform.sessionManager;
    final bridge = RunTerminalBridge(outputStream: manager.outputStream);
    for (final session in cubit.state.sessions) {
      final buffered = manager.bufferedOutputFor(session.id);
      if (buffered.isNotEmpty) {
        bridge.seed(session.id, buffered);
      }
    }
    setState(() {
      _ownedBridge = bridge;
      _bridge = bridge;
    });
  }

  @override
  void dispose() {
    _ownedBridge?.dispose();
    super.dispose();
  }

  void _onSessions(List<RunSession> sessions) {
    final ids = sessions.map((s) => s.id).toList();
    final previous = _seenSessionIds.toSet();
    final added = ids.where((id) => !previous.contains(id)).toList();
    _seenSessionIds = ids;

    String? nextActive = _activeSessionId;
    if (added.isNotEmpty) {
      nextActive = added.last;
    } else if (nextActive != null && !ids.contains(nextActive)) {
      nextActive = ids.isEmpty ? null : ids.last;
    } else if (nextActive == null && ids.isNotEmpty) {
      nextActive = ids.last;
    }

    if (nextActive != _activeSessionId) {
      setState(() => _activeSessionId = nextActive);
    }
  }

  Future<void> _closeSession(RunSession session) async {
    final running =
        session.status == RunSessionStatus.running ||
        session.status == RunSessionStatus.starting;
    if (running) {
      final l10n = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                title: l10n.runStopSessionTitle,
                onClose: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.runStopSessionMessage(session.owned.configuration.name),
              ),
              AppDialogActions(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(l10n.runStopAndClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final cubit = context.read<RunCubit>();
    await cubit.dismissSession(session.id);
    _bridge?.clear(session.id);
  }

  Future<void> _clearExited() async {
    final bridge = _bridge;
    if (bridge == null) return;

    final cubit = context.read<RunCubit>();
    final exited = cubit.state.sessions
        .where(
          (s) =>
              s.status == RunSessionStatus.exited ||
              s.status == RunSessionStatus.failed,
        )
        .map((s) => s.id)
        .toList();
    for (final id in exited) {
      await cubit.dismissSession(id);
      bridge.clear(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    return BlocConsumer<RunCubit, RunState>(
      listenWhen: (prev, next) => prev.sessions != next.sessions,
      listener: (context, state) => _onSessions(state.sessions),
      buildWhen: (prev, next) => prev.sessions != next.sessions,
      builder: (context, state) {
        final sessions = state.sessions;
        RunSession? activeSession;
        for (final session in sessions) {
          if (session.id == _activeSessionId) {
            activeSession = session;
            break;
          }
        }
        activeSession ??= sessions.isEmpty ? null : sessions.last;

        return KeyedSubtree(
          key: const Key('run-panel'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: sessions.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  l10n.runNoSessions,
                                  style: styles.mutedSm,
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final session in sessions)
                                    WorkspaceShellTabChip(
                                      key: ValueKey(
                                        'run-session-tab-${session.id}',
                                      ),
                                      title: session.owned.configuration.name,
                                      active: session.id == activeSession?.id,
                                      working:
                                          session.status ==
                                              RunSessionStatus.running ||
                                          session.status ==
                                              RunSessionStatus.starting,
                                      onTap: () => setState(
                                        () => _activeSessionId = session.id,
                                      ),
                                      onClose: () => unawaited(
                                        _closeSession(session),
                                      ),
                                      accentColor: cs.primary,
                                      icon: Icons.play_arrow_rounded,
                                    ),
                                ],
                              ),
                            ),
                    ),
                    AppIconButton(
                      icon: Icons.close,
                      color: cs.onSurfaceVariant,
                      size: AppIconButton.kCompactSize,
                      tooltip: l10n.runClearExited,
                      onTap: () => unawaited(_clearExited()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _bridge == null
                    ? ColoredBox(
                        color: cs.surfaceContainerLowest,
                        child: Center(
                          child: Text(
                            l10n.runLoadingOutput,
                            style: styles.mutedMd,
                          ),
                        ),
                      )
                    : activeSession == null
                    ? ColoredBox(
                        color: cs.surfaceContainerLowest,
                        child: Center(
                          child: Text(
                            l10n.runEmptyOutputHint,
                            style: styles.mutedMd,
                          ),
                        ),
                      )
                    : RunSessionPage(
                        key: Key('run-session-page-${activeSession.id}'),
                        sessionId: activeSession.id,
                        bridge: _bridge!,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
