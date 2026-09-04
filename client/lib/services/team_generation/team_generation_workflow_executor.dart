import 'dart:async';

import '../../utils/lock_pool.dart';

/// Serializes workflow mutations (MCP entries, coordinator finalize/cancel,
/// commit effects) per `workspaceId/workflowId`. Repository substeps reached
/// from an already-serialized path must NOT enqueue again.
final class TeamGenerationWorkflowExecutor {
  TeamGenerationWorkflowExecutor({LockPool? locks}) : _locks = locks ?? LockPool();

  final LockPool _locks;

  Future<T> run<T>(
    String workspaceId,
    String workflowId,
    Future<T> Function() body,
  ) {
    return _locks.synchronized('$workspaceId/$workflowId', body);
  }
}
