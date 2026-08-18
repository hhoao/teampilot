import '../../../../models/team_config.dart';

/// Resource kinds assembled by the typed contribution pipeline.
enum ResourceContributionKind { prompt, skill, mcp, hook }

/// Categories of failures that prevent a resource assembly from completing.
enum ResourceAssemblyErrorKind { provider, conflict, unsupported }

/// Severity used by deterministic assembly diagnostics.
enum ResourceAssemblyDiagnosticSeverity { warning, error }

/// Structured information about a provider or assembly issue.
class ResourceAssemblyDiagnostic {
  const ResourceAssemblyDiagnostic({
    required this.severity,
    required this.resourceKind,
    required this.cli,
    required this.providerId,
    this.sourceId,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final ResourceAssemblyDiagnosticSeverity severity;
  final ResourceContributionKind resourceKind;
  final CliTool cli;
  final String providerId;
  final String? sourceId;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceAssemblyDiagnostic &&
          runtimeType == other.runtimeType &&
          severity == other.severity &&
          resourceKind == other.resourceKind &&
          cli == other.cli &&
          providerId == other.providerId &&
          sourceId == other.sourceId &&
          message == other.message;

  @override
  int get hashCode =>
      Object.hash(severity, resourceKind, cli, providerId, sourceId, message);

  @override
  String toString() =>
      'ResourceAssemblyDiagnostic(severity: $severity, '
      'resourceKind: $resourceKind, cli: ${cli.value}, '
      'providerId: $providerId, sourceId: $sourceId, message: $message)';
}

/// An error diagnostic with a specific failure category.
class ResourceAssemblyError extends ResourceAssemblyDiagnostic {
  const ResourceAssemblyError._({
    required this.errorKind,
    required super.resourceKind,
    required super.cli,
    required super.providerId,
    super.sourceId,
    required super.message,
    super.cause,
    super.stackTrace,
  }) : super(severity: ResourceAssemblyDiagnosticSeverity.error);

  const ResourceAssemblyError.provider({
    required ResourceContributionKind resourceKind,
    required CliTool cli,
    required String providerId,
    String? sourceId,
    required String message,
    Object? cause,
    StackTrace? stackTrace,
  }) : this._(
         errorKind: ResourceAssemblyErrorKind.provider,
         resourceKind: resourceKind,
         cli: cli,
         providerId: providerId,
         sourceId: sourceId,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
       );

  const ResourceAssemblyError.conflict({
    required ResourceContributionKind resourceKind,
    required CliTool cli,
    required String providerId,
    String? sourceId,
    required String message,
  }) : this._(
         errorKind: ResourceAssemblyErrorKind.conflict,
         resourceKind: resourceKind,
         cli: cli,
         providerId: providerId,
         sourceId: sourceId,
         message: message,
       );

  const ResourceAssemblyError.unsupported({
    required ResourceContributionKind resourceKind,
    required CliTool cli,
    required String providerId,
    String? sourceId,
    required String message,
  }) : this._(
         errorKind: ResourceAssemblyErrorKind.unsupported,
         resourceKind: resourceKind,
         cli: cli,
         providerId: providerId,
         sourceId: sourceId,
         message: message,
       );

  final ResourceAssemblyErrorKind errorKind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceAssemblyError &&
          errorKind == other.errorKind &&
          super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, errorKind);

  @override
  String toString() =>
      'ResourceAssemblyError(kind: $errorKind, ${super.toString()})';
}

/// Exception raised when one or more resource assembly errors are fatal.
class ResourceAssemblyException implements Exception {
  ResourceAssemblyException(Iterable<ResourceAssemblyError> diagnostics)
    : diagnostics = _validateDiagnostics(diagnostics) {
    if (this.diagnostics.isEmpty) {
      throw ArgumentError.value(
        diagnostics,
        'diagnostics',
        'must not be empty',
      );
    }
  }

  final List<ResourceAssemblyError> diagnostics;

  static List<ResourceAssemblyError> _validateDiagnostics(
    Iterable<ResourceAssemblyError> diagnostics,
  ) {
    return List.unmodifiable(diagnostics);
  }

  @override
  String toString() => 'ResourceAssemblyException(${diagnostics.join('; ')})';
}
