import '../../models/app_provider_config.dart';
import '../io/filesystem.dart';
import 'codex_config_toml_composer.dart';
import 'codex_proxy_launch_auth.dart';
import 'tool_config_generator.dart';

/// Materializes `auth.json` and `config.toml` under a Codex `CODEX_HOME`.
final class CodexHomeProvisioner {
  CodexHomeProvisioner({
    ToolConfigGenerator? generator,
    CodexConfigTomlComposer? composer,
    Filesystem? fs,
  }) : _generator = generator ?? const ToolConfigGenerator(),
       _composer =
           composer ??
           CodexConfigTomlComposer(
             generator: generator ?? const ToolConfigGenerator(),
           ),
       _fs = fs;

  final ToolConfigGenerator _generator;
  final CodexConfigTomlComposer _composer;
  final Filesystem? _fs;

  static const authFileName = 'auth.json';
  static const configFileName = 'config.toml';

  Future<void> provision({
    required String codexHome,
    required AppProviderConfig provider,
    String? busOverlayToml,
    Iterable<String> trustedProjectDirectories = const [],
  }) async {
    final store = _fs;
    if (store == null) {
      throw StateError('CodexHomeProvisioner requires a Filesystem');
    }

    final auth = CodexProxyLaunchAuth.buildAuth(provider, generator: _generator);
    final toml = _composer.compose(
      provider: provider,
      busOverlayToml: busOverlayToml,
      trustedProjectDirectories: trustedProjectDirectories,
    );

    final error = _generator.validateCodexToml(toml);
    if (error != null) {
      throw CodexHomeProvisionException(
        'Codex config.toml invalid for ${provider.id}: $error',
      );
    }

    await store.ensureDir(codexHome);
    await _generator.writeJsonAtomic(
      store.pathContext.join(codexHome, authFileName),
      auth,
      fs: store,
    );
    if (toml.trim().isNotEmpty) {
      await _generator.writeTextAtomic(
        store.pathContext.join(codexHome, configFileName),
        toml,
        fs: store,
      );
    }
  }
}

final class CodexHomeProvisionException implements Exception {
  CodexHomeProvisionException(this.message);

  final String message;

  @override
  String toString() => message;
}
