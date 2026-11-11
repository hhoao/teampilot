import '../../../models/team_config.dart';

/// Distribution-specific Qoder CLI identity.
///
/// The global and CN builds share the same ACP protocol and config-dir
/// contract, but they are separate binaries with separate provider catalogs
/// and separate account stores.
final class QoderFlavor {
  const QoderFlavor({
    required this.cli,
    required this.executableName,
    required this.displayName,
    required this.providerId,
    required this.providerLabel,
    required this.websiteUrl,
    required this.installUrl,
    required this.authNamespace,
    required this.configDirEnvKey,
    required this.tokenUsageEnvKey,
    required this.allowMachineAuthFallback,
  });

  final CliTool cli;
  final String executableName;
  final String displayName;
  final String providerId;
  final String providerLabel;
  final String websiteUrl;
  final String installUrl;
  final String authNamespace;

  /// Env var the binary reads for its config dir (and `.auth`). The CN build
  /// ignores the global key.
  final String configDirEnvKey;

  /// Env var that opts the binary into writing real token counts.
  ///
  /// Both builds zero `input_tokens`/`output_tokens`/cache counts in their
  /// transcripts and SDK output by default; only `credits` and
  /// `context_usage_ratio` stay populated. TeamPilot's usage collector reads
  /// those transcripts, so every launch sets this to `1`.
  final String tokenUsageEnvKey;

  final bool allowMachineAuthFallback;

  static const global = QoderFlavor(
    cli: CliTool.qoder,
    executableName: 'qodercli',
    displayName: 'Qoder CLI',
    providerId: 'qoder',
    providerLabel: 'Qoder',
    websiteUrl: 'https://qoder.com',
    installUrl: 'https://download.qoder.com/qodercli/install.sh',
    authNamespace: 'qoder',
    configDirEnvKey: 'QODER_CONFIG_DIR',
    tokenUsageEnvKey: 'QODER_EXPOSE_TOKEN_USAGE',
    allowMachineAuthFallback: true,
  );

  static const cn = QoderFlavor(
    cli: CliTool.qoderCn,
    executableName: 'qoderclicn',
    displayName: 'Qoder CLI CN',
    providerId: 'qoder-cn',
    providerLabel: 'Qoder CN',
    websiteUrl: 'https://qoder.com.cn',
    installUrl: 'https://qoder.com.cn/install',
    authNamespace: 'qoder-cn',
    configDirEnvKey: 'QODERCN_CONFIG_DIR',
    tokenUsageEnvKey: 'QODERCN_EXPOSE_TOKEN_USAGE',
    allowMachineAuthFallback: false,
  );

  bool get isCn => cli == CliTool.qoderCn;
}
