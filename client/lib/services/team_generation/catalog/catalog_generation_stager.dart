import '../../catalog/catalog_kind.dart';
import '../../io/filesystem.dart';
import '../../storage/app_storage.dart';
import '../../storage/workspace_layout.dart';
import '../models/team_generation_job.dart';
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
final class CatalogGenerationStager {
  CatalogGenerationStager({
    required TeamGenerationJobStore jobStore,
    required TeamGenerationWorkflowExecutor executor,
    WorkspaceLayout? layout,
    Filesystem? fs,
  }) : _jobStore = jobStore,
       _executor = executor,
       _layoutOverride = layout,
       _fsOverride = fs;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationWorkflowExecutor _executor;
  final WorkspaceLayout? _layoutOverride;
  final Filesystem? _fsOverride;

  TeamGenerationJobStore get jobStore => _jobStore;
  TeamGenerationWorkflowExecutor get executor => _executor;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  WorkspaceLayout get _layout =>
      _layoutOverride ?? WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  /// Entry point used by every mutating catalog handler when the request is
  /// generation-scoped. Runs inside the shared workflow executor.
  Future<CatalogResult> handleMcpMutation({
    required String kind,
    required CatalogOp op,
    required CatalogRequest request,
  }) {
    return executor.run(request.workspaceId, request.workflowId, () async {
      final job = await jobStore.read(request.workspaceId, request.workflowId);
      if (job == null || !job.isActive) {
        throw CatalogException(
          'generation_staging_unsupported',
          'workflow is not active',
        );
      }
      final staged = TeamGenerationStagedResource(
        kind: kind,
        refId: '${request.arguments['id'] ?? request.arguments['name'] ?? ''}',
        stagedPath: _stagingPathFor(kind, request),
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

  String _stagingPathFor(String kind, CatalogRequest request) {
    final dir = _layout.teamGenerationStagingDir(
      request.workspaceId,
      request.workflowId,
    );
    return _fs.pathContext.join(dir, kind);
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
            TeamGenerationStagedResource(
              kind: kind,
              refId: id,
              stagedPath: '',
            ),
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
