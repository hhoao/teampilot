import '../io/filesystem.dart';

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

enum CatalogBindTo { workspace }

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
  });

  final String sessionId;
  final String workspaceId;
  final String? memberId;
  final CatalogBindTo bindTo;
  final bool overwrite;
  final Map<String, Object?> arguments;
  final Filesystem workFs;
  final List<String> allowedRoots;
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
