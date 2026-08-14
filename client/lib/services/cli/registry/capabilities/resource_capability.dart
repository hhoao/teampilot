import '../../../resource/resource_kind.dart';
import '../cli_capability.dart';
import 'skill_capability.dart';

/// Declares, per-CLI, which plugin resource kinds it consumes and how they
/// land in its CONFIG_DIR. Contains NO provisioning logic — the shared
/// materializer does the work; this just describes the target shape.
abstract interface class ResourceCapability implements CliCapability {
  Set<ResourceKind> get supportedKinds;

  /// Subdirectory (relative to the CONFIG_DIR) where this kind's entries live,
  /// for `linkedDirectory` kinds (e.g. 'plugins').
  ///
  /// Precondition: [kind] must be in [supportedKinds]; the returned value is
  /// unspecified for unsupported kinds. Callers must guard with
  /// `supportedKinds.contains(kind)` before calling.
  String subdirFor(ResourceKind kind);

  /// How [kind] is represented inside the CLI's CONFIG_DIR.
  ///
  /// Precondition: [kind] must be in [supportedKinds]; the returned value is
  /// unspecified for unsupported kinds. Callers must guard with
  /// `supportedKinds.contains(kind)` before calling.
  ResourceRepresentation representationFor(ResourceKind kind);
}
