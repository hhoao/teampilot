import '../../registry/capabilities/executable_resolver_capability.dart';

final class ClaudeExecutableResolver implements ExecutableResolverCapability {
  const ClaudeExecutableResolver();
  @override
  String get defaultExecutableName => 'claude';
  @override
  String get preferencesPathKey => 'claude';
}
