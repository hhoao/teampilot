import 'dart:convert';

import '../../catalog/catalog_kind.dart';
import '../../catalog/catalog_kind_registry.dart';
import '../../io/filesystem.dart';
import '../../storage/app_storage.dart';
import '../../storage/workspace_layout.dart';
import '../models/team_generation_job.dart';
import '../generated_team_commit_service.dart';
import '../team_generation_job_store.dart';
import '../team_generation_workflow_executor.dart';

/// One staged catalog resource reference recorded on the job.
/// (Reuses [TeamGenerationStagedResource] for JSON round-trip.)

/// Workflow-scoped catalog staging: copies validated payloads into the
/// workflow's `staging/` directory, records references on the job, promotes
/// staged resources into real repositories at finalize, and compensates
/// workflow-owned effects on pre-profile failure.
///
/// Normal catalog policy is untouched: modules delegate here only when
/// `req.bindTo == CatalogBindTo.generation`.
final class CatalogGenerationStager
    implements
        CatalogGenerationMutationHandler,
        TeamGenerationResourcePromoter {
  CatalogGenerationStager({
    required TeamGenerationJobStore jobStore,
    required TeamGenerationWorkflowExecutor executor,
    WorkspaceLayout? layout,
    Filesystem? fs,
    CatalogKindRegistry? registry,
  }) : _jobStore = jobStore,
       _executor = executor,
       _layoutOverride = layout,
       _fsOverride = fs,
       _registry = registry;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationWorkflowExecutor _executor;
  final WorkspaceLayout? _layoutOverride;
  final Filesystem? _fsOverride;
  final CatalogKindRegistry? _registry;

  TeamGenerationJobStore get jobStore => _jobStore;
  TeamGenerationWorkflowExecutor get executor => _executor;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  WorkspaceLayout get _layout =>
      _layoutOverride ??
      WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  /// Entry point used by every mutating catalog handler when the request is
  /// generation-scoped. Runs inside the shared workflow executor.
  @override
  Future<CatalogResult> handleMcpMutation({
    required String kind,
    required CatalogOp op,
    required CatalogRequest request,
  }) {
    return executor.run(request.workspaceId, request.workflowId, () async {
      if (!catalogGenerationAcquisitionOps.contains(op)) {
        throw CatalogException(
          'generation_mutation_forbidden',
          '${op.name} is not allowed in generation scope',
        );
      }
      final job = await jobStore.read(request.workspaceId, request.workflowId);
      if (job == null || !job.isActive) {
        throw CatalogException(
          'generation_staging_unsupported',
          'workflow is not active',
        );
      }
      final refId = _refIdFor(request);
      final stagedPath = _stagingPathFor(
        request.workspaceId,
        request.workflowId,
        kind,
        refId,
      );
      await _fs.ensureDir(_fs.pathContext.dirname(stagedPath));
      await _fs.atomicWrite(
        stagedPath,
        jsonEncode({
          'op': op.name,
          'arguments': request.arguments,
          'overwrite': request.overwrite,
        }),
      );
      final staged = TeamGenerationStagedResource(
        kind: kind,
        refId: refId,
        stagedPath: stagedPath,
        createdAt: job.updatedAt,
      );
      final updated = await jobStore.mutate(
        job.workspaceId,
        job.workflowId,
        (current) => current.copyWith(
          stagedResources: [...current.stagedResources, staged],
        ),
      );
      return CatalogResult.ok(
        kind: kind,
        ids: [staged.refId],
        workspaceId: request.workspaceId,
        boundTo: CatalogBindTo.generation,
        message: 'staged:${updated.stagedResources.length}',
      );
    });
  }

  String _stagingPathFor(
    String workspaceId,
    String workflowId,
    String kind,
    String refId,
  ) {
    final dir = _layout.teamGenerationStagingDir(workspaceId, workflowId);
    return _fs.pathContext.join(dir, kind, '$refId.json');
  }

  String _refIdFor(CatalogRequest request) {
    final raw = '${request.arguments['id'] ?? request.arguments['name'] ?? ''}'
        .trim();
    if (raw.isEmpty) {
      throw CatalogException(
        'invalid_args',
        'generation resource requires id or name',
      );
    }
    return raw;
  }

  /// Promotes staged payloads through the regular catalog modules only after
  /// the generated profile has crossed its durable commit boundary.
  @override
  Future<void> promote({
    required String workspaceId,
    required String workflowId,
  }) {
    return executor.run(workspaceId, workflowId, () async {
      final registry = _registry;
      if (registry == null) return;
      final job = await jobStore.read(workspaceId, workflowId);
      if (job == null) throw StateError('missing workflow: $workflowId');
      for (final resource in job.stagedResources) {
        if (resource.stagedPath.isEmpty) continue;
        final raw = await _fs.readString(resource.stagedPath);
        if (raw == null)
          throw StateError('missing staged resource: ${resource.refId}');
        final payload = (jsonDecode(raw) as Map).cast<String, Object?>();
        final op = CatalogOp.values.byName(payload['op'] as String);
        final module = registry.module(resource.kind);
        if (module == null)
          throw StateError('unknown catalog kind: ${resource.kind}');
        final args = (payload['arguments'] as Map).cast<String, Object?>();
        await module.handle(
          op,
          CatalogRequest(
            sessionId: 'team-generation-commit',
            workspaceId: workspaceId,
            bindTo: CatalogBindTo.team,
            overwrite: payload['overwrite'] == true,
            arguments: args,
            workFs: _fs,
            allowedRoots: const [],
          ),
        );
        await _fs.removeRecursive(resource.stagedPath);
      }
    });
  }

  @override
  Future<bool> isPromotionComplete({
    required String workspaceId,
    required String workflowId,
  }) async {
    final job = await jobStore.read(workspaceId, workflowId);
    if (job == null) return false;
    for (final resource in job.stagedResources) {
      if (resource.stagedPath.isNotEmpty &&
          (await _fs.stat(resource.stagedPath)).exists) {
        return false;
      }
    }
    return true;
  }

  /// Records a reference to an already-installed resource (no copy).
  Future<void> reference({
    required String workspaceId,
    required String workflowId,
    required String kind,
    required String id,
  }) {
    return executor.run(workspaceId, workflowId, () async {
      await jobStore.mutate(workspaceId, workflowId, (current) {
        final existing = current.stagedResources.any(
          (resource) => resource.kind == kind && resource.refId == id,
        );
        if (existing) return current.copyWith();
        return current.copyWith(
          stagedResources: [
            ...current.stagedResources,
            TeamGenerationStagedResource(kind: kind, refId: id, stagedPath: ''),
          ],
        );
      });
    });
  }

  /// Compensates workflow-owned staged resources: references are dropped,
  /// staged payloads are deleted. Never touches globally installed resources
  /// another workflow or user created.
  Future<void> compensate({
    required String workspaceId,
    required String workflowId,
  }) {
    return executor.run(workspaceId, workflowId, () async {
      final job = await jobStore.read(workspaceId, workflowId);
      if (job == null) return;
      for (final resource in job.stagedResources) {
        if (resource.stagedPath.isEmpty) continue;
        final stat = await _fs.stat(resource.stagedPath);
        if (stat.exists) {
          await _fs.removeRecursive(resource.stagedPath);
        }
      }
      await jobStore.mutate(workspaceId, workflowId, (current) {
        return current.copyWith(stagedResources: const []);
      });
    });
  }
}
