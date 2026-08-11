import '../../registry/capabilities/executable_resolver_capability.dart';

final class FlashskyaiExecutableResolver implements ExecutableResolverCapability {
  const FlashskyaiExecutableResolver();
  @override
  String get defaultExecutableName => 'flashskyai';
  @override
  String get preferencesPathKey => 'flashskyai';
}
