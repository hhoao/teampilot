import '../../../models/app_provider_config.dart';
import 'codex_toml_parser.dart';
import '../tool_config_generator.dart';

/// Chooses `auth.json` contents for Codex launch (proxy vs direct API key).
abstract final class CodexProxyLaunchAuth {
  CodexProxyLaunchAuth._();

  static bool usesProxyManagedToken(AppProviderConfig provider) {
    final meta = provider.config['meta'];
    if (meta is Map && meta['proxyTakeover'] == true) return true;

    final toml =
        provider.config['configToml']?.toString() ??
        provider.config['config_toml']?.toString() ??
        '';
    return CodexTomlParser.detectProxyTakeover(
      liveToml: toml,
      liveAuth: const {},
    );
  }

  static Map<String, Object?> buildAuth(
    AppProviderConfig provider, {
    ToolConfigGenerator? generator,
  }) {
    final gen = generator ?? const ToolConfigGenerator();
    final auth = Map<String, Object?>.from(gen.buildCodexAuth(provider));
    if (usesProxyManagedToken(provider)) {
      auth['OPENAI_API_KEY'] = CodexTomlParser.proxyManagedToken;
    }
    return auth;
  }
}
