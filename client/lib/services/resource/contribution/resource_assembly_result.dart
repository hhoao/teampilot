import 'resource_assembly_error.dart';

/// Deterministic output shared by resource assemblers.
class ResourceAssemblyResult {
  factory ResourceAssemblyResult({
    required Iterable<ResourceAssemblyDiagnostic> diagnostics,
  }) {
    final ordered = List<ResourceAssemblyDiagnostic>.unmodifiable(diagnostics);
    return ResourceAssemblyResult._fromDiagnostics(ordered);
  }

  ResourceAssemblyResult._fromDiagnostics(
    List<ResourceAssemblyDiagnostic> diagnostics,
  ) : diagnostics = List.unmodifiable(diagnostics),
      warnings = List.unmodifiable(
        diagnostics.where(
          (diagnostic) =>
              diagnostic.severity == ResourceAssemblyDiagnosticSeverity.warning,
        ),
      ),
      errors = List.unmodifiable(
        diagnostics.where(
          (diagnostic) =>
              diagnostic.severity == ResourceAssemblyDiagnosticSeverity.error,
        ),
      );

  final List<ResourceAssemblyDiagnostic> warnings;
  final List<ResourceAssemblyDiagnostic> errors;
  final List<ResourceAssemblyDiagnostic> diagnostics;
}
