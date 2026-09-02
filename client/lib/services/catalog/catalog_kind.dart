import '../io/filesystem.dart';
import '../../models/app_session.dart';

enum CatalogOp {
  search,
  list,
  read,
  install,
  importPath,
  create,
  update,
  unbind,
  delete,
}

const catalogGenerationAcquisitionOps = <CatalogOp>{
  CatalogOp.install,
  CatalogOp.importPath,
  CatalogOp.create,
};

enum CatalogBindTo { workspace, team, expert, generation }

class CatalogException implements Exception {
  CatalogException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'CatalogException($code): $message';
}

class CatalogFailure {
  const CatalogFailure({
    required this.path,
    required this.code,
    required this.message,
  });

  final String path;
  final String code;
  final String message;
}

class CatalogRequest {
  CatalogRequest({
    required this.sessionId,
    required this.workspaceId,
    this.memberId,
    this.bindTo = CatalogBindTo.workspace,
    this.overwrite = false,
    required this.arguments,
    required this.workFs,
    required this.allowedRoots,
    this.purpose = SessionPurpose.normal,
    this.workflowId = '',
  });

  final String sessionId;
  final String workspaceId;
  final String? memberId;
  final CatalogBindTo bindTo;

  /// Team-generation workflow id; non-empty only for builder sessions that
  /// pass `bind_to: generation`. Never model-supplied — resolved from the
  /// persisted session by [CatalogRuntime.resolveCatalogSession].
  final String workflowId;
  final bool overwrite;
  final Map<String, Object?> arguments;
  final Filesystem workFs;
  final List<String> allowedRoots;

  /// Persisted session purpose used to authorize generation-only mutations.
  final SessionPurpose purpose;
}

/// Workflow-scoped mutation seam. It keeps the catalog transport independent
/// from the generation implementation while ensuring builder mutations never
/// reach normal catalog modules before commit.
abstract interface class CatalogGenerationMutationHandler {
  Future<CatalogResult> handleMcpMutation({
    required String kind,
    required CatalogOp op,
    required CatalogRequest request,
  });
}

class CatalogResult {
  const CatalogResult({
    required this.ok,
    required this.kind,
    required this.ids,
    required this.workspaceId,
    required this.restartRequired,
    this.boundTo,
    this.message,
    this.data,
    this.failed,
  });

  final bool ok;
  final String kind;
  final List<String> ids;
  final String workspaceId;
  final bool restartRequired;
  final CatalogBindTo? boundTo;
  final String? message;
  final Map<String, Object?>? data;
  final List<CatalogFailure>? failed;

  factory CatalogResult.ok({
    required String kind,
    required List<String> ids,
    required String workspaceId,
    bool restartRequired = true,
    CatalogBindTo boundTo = CatalogBindTo.workspace,
    String? message,
    Map<String, Object?>? data,
  }) {
    return CatalogResult(
      ok: true,
      kind: kind,
      ids: ids,
      workspaceId: workspaceId,
      restartRequired: restartRequired,
      boundTo: boundTo,
      message: message,
      data: data,
    );
  }

  factory CatalogResult.partial({
    required String kind,
    required List<String> ids,
    required String workspaceId,
    required List<CatalogFailure> failed,
    bool restartRequired = true,
    CatalogBindTo boundTo = CatalogBindTo.workspace,
    String? message,
    Map<String, Object?>? data,
  }) {
    return CatalogResult(
      ok: false,
      kind: kind,
      ids: ids,
      workspaceId: workspaceId,
      restartRequired: restartRequired,
      boundTo: boundTo,
      message: message,
      data: data,
      failed: failed,
    );
  }
}

class CatalogToolSpec {
  const CatalogToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.mutating,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final bool mutating;
}

abstract interface class CatalogKindModule {
  String get kind;

  bool get supportsCreate;

  bool get supportsImport;

  bool get supportsInstall;

  List<CatalogToolSpec> advertise();

  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req);
}
