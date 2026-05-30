import '../cli_capability.dart';

abstract interface class ExecutableResolverCapability implements CliCapability {
  String get defaultExecutableName;
  String get preferencesPathKey;
}
