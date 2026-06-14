import '../../../resource/resource_kind.dart';
import '../capabilities/resource_capability.dart';

/// Default: skills land in a `skills/` directory. Plugin/MCP support is added
/// by their follow-on plans (extend [supportedKinds] then).
final class DefaultResourceCapability implements ResourceCapability {
  const DefaultResourceCapability();

  @override
  Set<ResourceKind> get supportedKinds => const {ResourceKind.skill};

  @override
  String subdirFor(ResourceKind kind) => switch (kind) {
        ResourceKind.skill => 'skills',
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
