import '../../registry/capabilities/executable_resolver_capability.dart';

final class CursorExecutableResolver implements ExecutableResolverCapability {
  const CursorExecutableResolver();
  @override
  String get defaultExecutableName => 'cursor-agent';
  @override
  String get preferencesPathKey => 'cursor';
}
