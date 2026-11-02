import 'dart:io';

import '../../registry/capabilities/headless_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';

/// One-shot support lands in Task 5; registered now so the registry shape is
/// stable.
final class QoderHeadlessCapability implements HeadlessCapability {
  const QoderHeadlessCapability();

  @override
  String get executable => 'qodercli';

  @override
  bool get isSupported => false;

  @override
  bool get supportsStreaming => false;

  @override
  bool get supportsPromptStdin => false;

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    'QODER_CONFIG_DIR': context.configDir,
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessLaunchContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) => const [];

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();

  @override
  String? streamResultText(String line) => null;

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async => const HeadlessProvisionResult();
}
