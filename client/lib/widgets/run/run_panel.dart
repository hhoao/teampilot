import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/run_session.dart';
import '../../pages/workspace_shell/workspace_shell_tabs.dart';
import '../../services/run/run_platform.dart';
import '../../services/run/run_terminal_bridge.dart';
import 'package:shared_ui/shared_ui.dart';
import 'run_session_dismiss.dart';
import 'run_session_display_order.dart';
import 'run_session_page.dart';

/// Bottom Run pages: one tab per [RunSession], text log via [RunTerminalBridge].
///
/// When [showChrome] is false (unified workspace dock), only the output body is
/// shown and [activeSessionId] is owned by the parent.
class RunPanel extends StatefulWidget {
  const RunPanel({
    this.bridge,
    this.showChrome = true,
    this.activeSessionId,
    super.key,
  });

  /// Injected for tests; defaults to listening on [RunCubit] session output.
  final RunTerminalBridge? bridge;

  /// When false, hides the internal tab strip (dock owns unified chips).
  final bool showChrome;

  /// Active session when [showChrome] is false.
  final String? activeSessionId;

  @override
  State<RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends State<RunPanel> {
  RunTerminalBridge? _ownedBridge;
  RunTerminalBridge? _bridge;
  bool _bridgeInitStarted = false;
  String? _activeSessionId;
  List<String> _seenSessionIds = const [];
  List<String> _tabOrderIds = const [];

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

  @override
  void didUpdateWidget(covariant RunPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showChrome &&
        widget.activeSessionId != oldWidget.activeSessionId) {
      _activeSessionId = widget.activeSessionId;
    }
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
    if (!widget.showChrome) {
      final previous = _seenSessionIds.toSet();
      final removed = previous.difference(ids.toSet());
      for (final id in removed) {
        _bridge?.clear(id);
      }
      _seenSessionIds = ids;
      return;
    }

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
    final dismissed = await dismissRunSessionWithConfirm(
      context: context,
      cubit: context.read<RunCubit>(),
      session: session,
      onCleared: (id) => _bridge?.clear(id),
    );
    if (!dismissed || !mounted) return;
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

  String? get _effectiveActiveId =>
      widget.showChrome ? _activeSessionId : widget.activeSessionId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final l10n = context.l10n;
    return BlocConsumer<RunCubit, RunState>(
      listenWhen: (prev, next) => prev.sessions != next.sessions,
      listener: (context, state) => _onSessions(state.sessions),
      buildWhen: (prev, next) => prev.sessions != next.sessions,
      builder: (context, state) {
        final sessions = state.sessions;
        RunSession? activeSession;
        final activeId = _effectiveActiveId;
        for (final session in sessions) {
          if (session.id == activeId) {
            activeSession = session;
            break;
          }
        }
        if (widget.showChrome) {
          activeSession ??= sessions.isEmpty ? null : sessions.last;
        }

        final body = _bridge == null
            ? ColoredBox(
                color: cs.surfaceContainerLowest,
                child: Center(
                  child: Text(l10n.runLoadingOutput, style: styles.mutedMd),
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
              );

        if (!widget.showChrome) {
          return KeyedSubtree(key: const Key('run-panel'), child: body);
        }

        final orderedSessions = mergeDisplayOrderIds(
          items: sessions,
          idOf: (s) => s.id,
          orderIds: _tabOrderIds,
        );

        return KeyedSubtree(
          key: const Key('run-panel'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpTabStrip(
                metrics: TpTabStripMetrics.shell,
                showBottomBorder: true,
                itemCount: orderedSessions.length,
                itemKey: (i) =>
                    ValueKey('run-session-tab-${orderedSessions[i].id}'),
                onReorder: orderedSessions.length > 1
                    ? (oldIndex, newIndex) {
                        setState(() {
                          _tabOrderIds = reorderListItems(
                            orderedSessions.map((s) => s.id).toList(),
                            oldIndex,
                            newIndex,
                          );
                        });
                      }
                    : null,
                trailing: TpIconButton(
                  icon: Icons.close,
                  color: cs.onSurfaceVariant,
                  size: TpIconButton.kCompactSize,
                  tooltip: l10n.runClearExited,
                  onTap: () => unawaited(_clearExited()),
                ),
                itemBuilder: (context, index) {
                  if (orderedSessions.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final session = orderedSessions[index];
                  return WorkbenchStripTabChip(
                    title: session.owned.configuration.name,
                    active: session.id == activeSession?.id,
                    working:
                        session.status == RunSessionStatus.running ||
                        session.status == RunSessionStatus.starting,
                    onTap: () =>
                        setState(() => _activeSessionId = session.id),
                    onClose: () => unawaited(_closeSession(session)),
                    accentColor: cs.primary,
                    icon: Icons.play_arrow_rounded,
                  );
                },
                leading: sessions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.runNoSessions,
                            style: styles.mutedSm,
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
