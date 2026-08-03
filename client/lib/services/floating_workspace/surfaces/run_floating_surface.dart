import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../cubits/run_cubit.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../models/run/run_session.dart';
import '../../../pages/workbench/run_tab_surface.dart';
import '../../../widgets/run/run_session_dismiss.dart';
import '../../workbench/workbench_run_intent.dart';
import '../floating_surface.dart';

/// Floating surface that hosts [RunTabSurface] for one run session id.
///
/// Domain open is driven by run UI intents / launcher; [activate] is a no-op
/// because [RunPanel] receives [RunTabSurface.activeSessionId] from the tab.
class RunFloatingSurface extends FloatingSurface {
  RunFloatingSurface({
    required FloatingWorkspaceCubit floating,
    String? Function(String sessionId)? resolveTitle,
    RunCubit? Function(String workspaceId)? resolveCubit,
    Future<void> Function(String sessionId)? onDismiss,
  }) : _floating = floating,
       _resolveTitle = resolveTitle ?? ((_) => null),
       _resolveCubit = resolveCubit,
       _onDismiss = onDismiss;

  final FloatingWorkspaceCubit _floating;
  final String? Function(String sessionId) _resolveTitle;
  final RunCubit? Function(String workspaceId)? _resolveCubit;
  final Future<void> Function(String sessionId)? _onDismiss;

  @override
  String get id => 'run';

  @override
  FloatingEmptyAction? get emptyAction => null;

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final sessionId = payload is String ? payload.trim() : '';
    final resolved = sessionId.isEmpty ? null : _resolveTitle(sessionId)?.trim();
    final title = resolved != null && resolved.isNotEmpty
        ? resolved
        : (sessionId.isEmpty ? 'Run' : sessionId);
    return FloatingTab(
      id: sessionId.isEmpty ? 'run:' : floatingRunTabId(sessionId),
      surfaceId: id,
      title: title,
      payload: sessionId.isEmpty ? null : sessionId,
    );
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final sessionId = tab.payload;
    if (sessionId is! String || sessionId.isEmpty) {
      return const SizedBox.shrink();
    }
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    final cubit = _resolveCubit?.call(workspaceId);
    if (cubit == null) {
      return const SizedBox.shrink();
    }
    return BlocProvider<RunCubit>.value(
      value: cubit,
      child: RunTabSurface(sessionId: sessionId),
    );
  }

  @override
  Future<void> activate(FloatingTab tab) async {}

  @override
  Future<bool> canClose(FloatingTab tab, {BuildContext? context}) async {
    final sessionId = tab.payload;
    if (sessionId is! String || sessionId.isEmpty) return true;
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) return true;

    final cubit = _resolveCubit?.call(workspaceId);
    if (cubit == null) {
      if (_onDismiss != null) {
        await _onDismiss(sessionId);
        return true;
      }
      return true;
    }

    final session = _sessionById(cubit.state.sessions, sessionId);
    if (session == null) return true;

    if (context == null || !context.mounted) {
      final running =
          session.status == RunSessionStatus.running ||
          session.status == RunSessionStatus.starting;
      if (running) return false;
      await cubit.dismissSession(sessionId);
      return true;
    }

    return dismissRunSessionWithConfirm(
      context: context,
      cubit: cubit,
      session: session,
    );
  }

  RunSession? _sessionById(List<RunSession> sessions, String id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }
}
