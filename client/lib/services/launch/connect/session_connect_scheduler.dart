import 'dart:async';

import '../../../cubits/chat/model/chat_state.dart';
import '../../../cubits/chat/model/chat_tab.dart';
import '../../../utils/logging/logger.dart';
import 'session_connect_job.dart';

abstract interface class SessionConnectExecutorPort {
  Future<void> execute(SessionConnectJob job);
}

abstract interface class SessionConnectSchedulerPort {
  Future<void> enqueue(SessionConnectJob job, {bool waitForCompletion = false});

  void cancelForTab(ChatTab tab);
}

class SessionConnectScheduler implements SessionConnectSchedulerPort {
  SessionConnectScheduler({
    required this.executor,
    required this.postFrame,
    required this.isJobValid,
    required this.onBegin,
    required this.onFinish,
  });

  final SessionConnectExecutorPort executor;
  final PostFrameScheduler postFrame;
  final bool Function(SessionConnectJob job) isJobValid;
  final void Function(String sessionId) onBegin;
  final void Function(String sessionId) onFinish;

  final Map<String, _SessionConnectToken> _pending =
      <String, _SessionConnectToken>{};

  String key(SessionConnectJob job) => job.sessionId + '|' + job.memberId;

  @override
  Future<void> enqueue(
    SessionConnectJob job, {
    bool waitForCompletion = false,
  }) {
    final id = key(job);
    final existing = _pending[id];
    if (existing != null) {
      if (waitForCompletion) existing.reportErrors = true;
      return waitForCompletion ? existing.done.future : Future<void>.value();
    }
    final token = _SessionConnectToken(
      job.sessionId,
      job.memberId,
      reportErrors: waitForCompletion,
    );
    _pending[id] = token;
    job.tab.membersPendingConnect.add(job.memberId);
    onBegin(job.sessionId);
    if (waitForCompletion) {
      // Completion-aware callers are already awaiting the launch boundary.
      // Start their work now so the returned future cannot depend on a frame
      // that the caller may be waiting to pump (notably during tab
      // materialization). Fire-and-forget restore work remains post-frame.
      unawaited(_execute(job, id, token));
    } else {
      // Keep independent fire-and-forget jobs concurrent. Completion-aware
      // callers use the branch above; restore work must not serialize behind
      // another member's slow preparation.
      postFrame(() {
        unawaited(_execute(job, id, token));
      });
    }
    return waitForCompletion ? token.done.future : Future<void>.value();
  }

  Future<void> _execute(
    SessionConnectJob job,
    String id,
    _SessionConnectToken token,
  ) async {
    try {
      if (_pending[id] == token && !token.cancelled && isJobValid(job)) {
        await executor.execute(job);
      }
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[session-launch] unexpected executor failure',
        error: error,
        stackTrace: stackTrace,
      );
      if (!token.done.isCompleted) {
        if (token.reportErrors) {
          token.done.completeError(error, stackTrace);
        } else {
          token.done.complete();
        }
      }
    } finally {
      if (_pending[id] == token) {
        _pending.remove(id);
        job.tab.membersPendingConnect.remove(job.memberId);
        onFinish(job.sessionId);
      }
      if (!token.done.isCompleted) {
        token.done.complete();
      }
    }
  }

  bool isPending({required String sessionId, required String memberId}) =>
      _pending.containsKey(sessionId + '|' + memberId);

  @override
  void cancelForTab(ChatTab tab) {
    final prefix = '${tab.info.id}|';
    for (final entry in _pending.entries.toList()) {
      if (entry.key.startsWith(prefix)) {
        entry.value.cancelled = true;
        _pending.remove(entry.key);
        tab.membersPendingConnect.remove(entry.value.memberId);
        onFinish(entry.value.sessionId);
        if (!entry.value.done.isCompleted) {
          entry.value.done.complete();
        }
      }
    }
  }
}

final class _SessionConnectToken {
  _SessionConnectToken(
    this.sessionId,
    this.memberId, {
    required this.reportErrors,
  });

  final String sessionId;
  final String memberId;
  bool reportErrors;
  final Completer<void> done = Completer<void>();
  bool cancelled = false;
}
