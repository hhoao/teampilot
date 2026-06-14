import '../../../resource/resource_kind.dart';
import '../capabilities/resource_capability.dart';
import 'default_resource_capability.dart';

/// opencode names its skills directory `skill` (singular).
final class OpencodeResourceCapability implements ResourceCapability {
  const OpencodeResourceCapability();

  static const _base = DefaultResourceCapability();

  @override
  Set<ResourceKind> get supportedKinds => _base.supportedKinds;

  @override
  String subdirFor(ResourceKind kind) =>
      kind == ResourceKind.skill ? 'skill' : _base.subdirFor(kind);

  @override
  ResourceRepresentation representationFor(ResourceKind kind) =>
      _base.representationFor(kind);
}
