import 'dart:async';
import 'dart:convert';

import '../../../../utils/logging/logger.dart';
import '../models/team_generation_job.dart';
import '../team_generation_job_store.dart';
import '../team_generation_workflow_executor.dart';
import 'team_composer_mcp_constants.dart';

/// Principal resolved by the gateway for one composer request.
typedef TeamComposerPrincipalFactory = Future<ComposerPrincipal?> Function(
  String sessionId,
);

/// Immutable principal carried through dispatch.
final class ComposerPrincipal {
  const ComposerPrincipal({
    required this.sessionId,
    required this.workspaceId,
    required this.workflowId,
  });

  final String sessionId;
  final String workspaceId;
  final String workflowId;
}

/// Handler result: a JSON-RPC-ready payload plus an optional post-flush
/// callback that the gateway runs only after the response bytes are written
/// and the connection closed.
final class TeamComposerMcpResult {
  const TeamComposerMcpResult({
    required this.response,
    this.afterResponseFlushed,
  });

  final Map<String, Object?> response;
  final Future<void> Function()? afterResponseFlushed;
}

/// Context handed to the composer handler per workflow.
final class TeamComposerHandlerContext {
  const TeamComposerHandlerContext({
    required this.jobStore,
    required this.executor,
    required this.contextProvider,
    required this.probeRunner,
    required this.planValidator,
    required this.finalizer,
  });

  final TeamGenerationJobStore jobStore;
  final TeamGenerationWorkflowExecutor executor;

  /// Returns the immutable generation context for a valid job.
  final Future<Map<String, Object?>> Function(TeamGenerationJob job)
  contextProvider;

  /// Runs a target probe and returns the redacted probe snapshot.
  final Future<Map<String, Object?>> Function(TeamGenerationJob job)
  probeRunner;

  /// Validates the supplied plan JSON and returns
  /// `(valid, issues, normalizedPlan, revision, destination)`.
  final Future<PlanValidationOutcome> Function(
    TeamGenerationJob job,
    Map<String, Object?> plan,
  )
  planValidator;

  /// Performs the receipt-driven commit + handoff. Runs after the accepted
  /// finalize response is flushed.
  final Future<void> Function(TeamGenerationJob job, String idempotencyKey)
  finalizer;
}

/// Pure outcome of one plan validation.
final class PlanValidationOutcome {
  const PlanValidationOutcome({
    required this.valid,
    required this.issues,
    required this.normalizedPlan,
    required this.revision,
    this.destination,
  });

  final bool valid;
  final List<Map<String, Object?>> issues;
  final Map<String, Object?> normalizedPlan;
  final String revision;
  final Map<String, Object?>? destination;
}

/// JSON-RPC tool dispatcher for the Team Composer MCP.
///
/// Authorization happens at the gateway (token + principal); this handler
/// re-checks the durable job before every mutating tool and serializes
/// mutations through the shared [TeamGenerationWorkflowExecutor].
final class TeamComposerMcpHandler {
  TeamComposerMcpHandler({required this.context});

  final TeamComposerHandlerContext context;

  static const protocolVersion = TeamComposerMcpConstants.protocolVersion;

  /// Tool schemas with `additionalProperties: false` everywhere.
  Map<String, Object?> toolSchemas() => {
    for (final name in TeamComposerToolName.all)
      name: _schemaFor(name),
  };

  Map<String, Object?> _schemaFor(String name) => switch (name) {
    TeamComposerToolName.getContext => {
      'type': 'object',
      'properties': const <String, Object?>{},
      'additionalProperties': false,
    },
    TeamComposerToolName.probeTargets => {
      'type': 'object',
      'properties': {
        'refresh': {'type': 'boolean'},
      },
      'additionalProperties': false,
    },
    TeamComposerToolName.validatePlan => {
      'type': 'object',
      'properties': {
        'plan': {'type': 'object'},
      },
      'required': ['plan'],
      'additionalProperties': false,
    },
    TeamComposerToolName.finalize => {
      'type': 'object',
      'properties': {
        'plan': {'type': 'object'},
        'validationRevision': {'type': 'string', 'minLength': 1},
        'idempotencyKey': {
          'type': 'string',
          'minLength': 1,
          'maxLength': 128,
          'pattern': r'^[A-Za-z0-9._:-]+$',
        },
      },
      'required': ['plan', 'validationRevision', 'idempotencyKey'],
      'additionalProperties': false,
    },
    _ => throw StateError('unknown tool $name'),
  };

  /// Handles one tools/call request for an already-authorized principal.
  Future<TeamComposerMcpResult> handleToolCall({
    required Object? requestId,
    required String toolName,
    required Map<String, Object?> arguments,
    required ComposerPrincipal principal,
  }) async {
    switch (toolName) {
      case TeamComposerToolName.getContext:
        // Read-only: no mutation queue.
        final job = await context.jobStore.read(
          principal.workspaceId,
          principal.workflowId,
        );
        if (job == null || !job.isActive) {
          return _toolError(requestId, 'workflow_not_active');
        }
        final payload = await context.contextProvider(job);
        return TeamComposerMcpResult(
          response: _toolPayload(requestId, payload),
        );

      case TeamComposerToolName.probeTargets:
      case TeamComposerToolName.validatePlan:
      case TeamComposerToolName.finalize:
        final result = await context.executor.run(
          principal.workspaceId,
          principal.workflowId,
          () => _handleMutating(
            requestId: requestId,
            toolName: toolName,
            arguments: arguments,
            principal: principal,
          ),
        );
        return result;
      default:
        return _toolError(requestId, 'unknown_tool');
    }
  }

  Future<TeamComposerMcpResult> _handleMutating({
    required Object? requestId,
    required String toolName,
    required Map<String, Object?> arguments,
    required ComposerPrincipal principal,
  }) async {
    // Re-read the durable job inside the queue (state may have changed).
    final job = await context.jobStore.read(
      principal.workspaceId,
      principal.workflowId,
    );
    if (job == null || !job.isActive) {
      return _toolError(requestId, 'workflow_not_active');
    }

    switch (toolName) {
      case TeamComposerToolName.probeTargets:
        final snapshot = await context.probeRunner(job);
        final advanced = await context.jobStore.mutate(
          job.workspaceId,
          job.workflowId,
          (current) => current.copyWith(
            phase: _advance(current.phase, TeamGenerationPhase.planning),
            probeSnapshotJson: snapshot,
            // New probe facts invalidate a previously validated plan.
            validatedRevision: '',
            validatedDestinationJson: null,
          ),
        );
        return TeamComposerMcpResult(
          response: _toolPayload(requestId, {
            'status': 'probed',
            'phase': advanced.phase.value,
          }),
        );

      case TeamComposerToolName.validatePlan:
        final plan = arguments['plan'];
        if (plan is! Map) {
          return _toolError(requestId, 'invalid_plan');
        }
        final outcome = await context.planValidator(
          job,
          plan.cast<String, Object?>(),
        );
        if (!outcome.valid) {
          // Record issues on the job without a validated revision.
          await context.jobStore.mutate(job.workspaceId, job.workflowId, (
            current,
          ) {
            return current.copyWith(
              normalizedPlanJson: outcome.normalizedPlan,
              planRevision: outcome.revision,
              validatedRevision: '',
              validatedDestinationJson: null,
            );
          });
          return TeamComposerMcpResult(
            response: _toolPayload(requestId, {
              'valid': false,
              'issues': outcome.issues,
              'revision': outcome.revision,
            }),
          );
        }
        final updated = await context.jobStore.mutate(
          job.workspaceId,
          job.workflowId,
          (current) => current.copyWith(
            phase: _advance(current.phase, TeamGenerationPhase.validating),
            normalizedPlanJson: outcome.normalizedPlan,
            planRevision: outcome.revision,
            validatedRevision: outcome.revision,
            validatedDestinationJson: outcome.destination,
          ),
        );
        return TeamComposerMcpResult(
          response: _toolPayload(requestId, {
            'valid': true,
            'issues': outcome.issues,
            'revision': updated.validatedRevision,
          }),
        );

      case TeamComposerToolName.finalize:
        return _finalize(
          requestId: requestId,
          arguments: arguments,
          job: job,
        );
      default:
        return _toolError(requestId, 'unknown_tool');
    }
  }

  Future<TeamComposerMcpResult> _finalize({
    required Object? requestId,
    required Map<String, Object?> arguments,
    required TeamGenerationJob job,
  }) async {
    final plan = arguments['plan'];
    final revision = (arguments['validationRevision'] as String?)?.trim() ?? '';
    final key = (arguments['idempotencyKey'] as String?)?.trim() ?? '';
    if (plan is! Map) {
      return _toolError(requestId, 'invalid_plan');
    }
    if (key.isEmpty || key.length > 128 || !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key)) {
      return _toolError(requestId, 'invalid_idempotency_key');
    }
    final current = await context.jobStore.read(job.workspaceId, job.workflowId);
    if (current == null || !current.isActive) {
      return _toolError(requestId, 'workflow_not_active');
    }

    // Idempotent replay with the same accepted key.
    final acceptedKey = current.finalizeIdempotencyKey;
    final profileSucceeded =
        current.receipts['profile']?.state ==
        TeamGenerationReceiptState.succeeded;
    if (acceptedKey.isNotEmpty) {
      if (acceptedKey == key) {
        return TeamComposerMcpResult(
          response: _toolPayload(requestId, {
            'accepted': true,
            'workflowId': current.workflowId,
            'phase': current.phase.value,
          }),
        );
      }
      // A different key after profile persistence is immutable.
      if (profileSucceeded) {
        return _toolError(requestId, 'immutable_commit');
      }
    }

    if (current.validatedRevision.isEmpty || current.validatedRevision != revision) {
      return _toolError(requestId, 'stale_validation_revision');
    }

    // Reserve + record acceptance before responding.
    var updated = await context.jobStore.mutate(
      current.workspaceId,
      current.workflowId,
      (running) => running.copyWith(
        phase: _advance(running.phase, TeamGenerationPhase.committing),
        finalizeIdempotencyKey: key,
      ),
    );
    updated = await context.jobStore.mutate(updated.workspaceId, updated.workflowId, (
      running,
    ) {
      return running.copyWith(
        receipts: {
          ...running.receipts,
          'finalizeAccepted': TeamGenerationReceipt(
            state: TeamGenerationReceiptState.succeeded,
            value: revision,
            updatedAt: running.updatedAt,
          ),
        },
      );
    });

    // The commit/handoff chain runs only after the response is flushed.
    return TeamComposerMcpResult(
      response: _toolPayload(requestId, {
        'accepted': true,
        'workflowId': updated.workflowId,
        'phase': updated.phase.value,
      }),
      afterResponseFlushed: () async {
        try {
          await context.finalizer(updated, key);
        } on Object catch (e, st) {
          appLogger.e(
            '[team-composer] post-flush finalize failed: $e\n$st',
          );
        }
      },
    );
  }

  TeamGenerationPhase _advance(TeamGenerationPhase from, TeamGenerationPhase to) {
    final fromRank = teamGenerationActivePhaseRank(from) ?? -1;
    final toRank = teamGenerationActivePhaseRank(to) ?? -1;
    return toRank >= fromRank ? to : from;
  }

  Map<String, Object?> _toolPayload(Object? requestId, Map<String, Object?> data) {
    return {
      'jsonrpc': '2.0',
      'id': requestId,
      'result': {
        'content': [
          {
            'type': 'text',
            'text': jsonEncode(data),
          },
        ],
        'structuredContent': data,
      },
    };
  }

  TeamComposerMcpResult _toolError(Object? requestId, String code) {
    return TeamComposerMcpResult(
      response: {
        'jsonrpc': '2.0',
        'id': requestId,
        'result': {
          'content': [
            {
              'type': 'text',
              'text': 'code=$code',
            },
          ],
          'isError': true,
          'structuredContent': {'code': code},
        },
      },
    );
  }
}
