import 'resource_assembly_error.dart';

/// Deterministic output shared by resource assemblers.
class ResourceAssemblyResult {
  ResourceAssemblyResult({
    Iterable<ResourceAssemblyDiagnostic> warnings = const [],
    Iterable<ResourceAssemblyDiagnostic> errors = const [],
    Iterable<ResourceAssemblyDiagnostic> diagnostics = const [],
  }) : warnings = List.unmodifiable(warnings),
       errors = List.unmodifiable(errors),
       diagnostics = List.unmodifiable(diagnostics);

  final List<ResourceAssemblyDiagnostic> warnings;
  final List<ResourceAssemblyDiagnostic> errors;
  final List<ResourceAssemblyDiagnostic> diagnostics;
}
