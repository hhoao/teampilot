import '../../../resource/resource_kind.dart';
import '../cli_capability.dart';

/// How a resource kind is represented inside a CLI's CONFIG_DIR.
enum ResourceRepresentation { linkedDirectory, mergedJsonEntry }

/// Declares, per-CLI, which resource kinds it consumes and how they land in its
/// CONFIG_DIR. Contains NO provisioning logic — the shared materializer does the
/// work; this just describes the target shape.
abstract interface class ResourceCapability implements CliCapability {
  Set<ResourceKind> get supportedKinds;

  /// Subdirectory (relative to the CONFIG_DIR) where this kind's entries live,
  /// for `linkedDirectory` kinds (e.g. 'skills', 'plugins').
  String subdirFor(ResourceKind kind);

  ResourceRepresentation representationFor(ResourceKind kind);
}
