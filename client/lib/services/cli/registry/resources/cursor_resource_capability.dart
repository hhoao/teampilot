import '../../../resource/resource_kind.dart';
import '../capabilities/resource_capability.dart';

/// Cursor-agent loads skills from `<cursorConfigDir>/skills-cursor/`.
final class CursorResourceCapability implements ResourceCapability {
  const CursorResourceCapability();

  static const skillsSubdirName = 'skills-cursor';

  @override
  Set<ResourceKind> get supportedKinds => const {ResourceKind.skill};

  @override
  String subdirFor(ResourceKind kind) => switch (kind) {
        ResourceKind.skill => skillsSubdirName,
        ResourceKind.plugin => 'plugins',
        ResourceKind.mcp => 'mcp',
      };

  @override
  ResourceRepresentation representationFor(ResourceKind kind) => switch (kind) {
        ResourceKind.skill => ResourceRepresentation.linkedDirectory,
        ResourceKind.plugin => ResourceRepresentation.linkedDirectory,
        ResourceKind.mcp => ResourceRepresentation.mergedJsonEntry,
      };
}
