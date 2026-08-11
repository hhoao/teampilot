import '../../registry/capabilities/executable_resolver_capability.dart';

final class CodexExecutableResolver implements ExecutableResolverCapability {
  const CodexExecutableResolver();
  @override
  String get defaultExecutableName => 'codex';
  @override
  String get preferencesPathKey => 'codex';
}
