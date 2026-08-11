import '../../registry/capabilities/executable_resolver_capability.dart';

final class OpencodeExecutableResolver implements ExecutableResolverCapability {
  const OpencodeExecutableResolver();
  @override
  String get defaultExecutableName => 'opencode';
  @override
  String get preferencesPathKey => 'opencode';
}
