import 'dart:convert';

import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import 'codex_auth_artifacts.dart';
import 'codex_config_sidecar.dart';
import 'codex_config_toml_composer.dart';
import 'codex_proxy_launch_auth.dart';
import 'codex_toml_parser.dart';
import '../capabilities/toml_merge.dart';
import '../../../provider/tool_config_generator.dart';

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
    String? storedAuthPath,
    String? reasoningEffortOverride,
    String? providerDir,
  }) async {
    final store = _fs;
    if (store == null) {
      throw StateError('CodexHomeProvisioner requires a Filesystem');
    }

    var auth = CodexProxyLaunchAuth.buildAuth(provider, generator: _generator);
    if (!CodexAuthArtifacts.mapIndicatesReady(auth) &&
        storedAuthPath != null &&
        storedAuthPath.trim().isNotEmpty) {
      final bytes = await store.readBytes(storedAuthPath);
      if (bytes != null) {
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map &&
              CodexAuthArtifacts.mapIndicatesReady(
                decoded.cast<String, Object?>(),
              )) {
            auth = Map<String, Object?>.from(decoded.cast<String, Object?>());
          }
        } on Object {
          // Keep generated auth when stored auth is unreadable.
        }
      }
    }
    final configPath = store.pathContext.join(codexHome, configFileName);
    final existingToml = await store.readString(configPath) ?? '';

    // Fail closed on a newly generated overlay Codex cannot parse. Leftover
    // `http` rows in an existing session file are stripped during merge.
    final overlay = busOverlayToml?.trim() ?? '';
    if (overlay.isNotEmpty) {
      final invalidOverlay = CodexTomlParser.invalidHookTypes(overlay);
      if (invalidOverlay.isNotEmpty) {
        throw CodexHomeProvisionException(
          'Codex config.toml has unsupported hook type(s) for ${provider.id}: '
          '${invalidOverlay.join(', ')} (allowed: '
          '${CodexTomlParser.allowedHookTypes.join(', ')})',
        );
      }
    }

    var toml = _composer.compose(
      provider: provider,
      busOverlayToml: busOverlayToml,
      trustedProjectDirectories: trustedProjectDirectories,
      reasoningEffortOverride: reasoningEffortOverride,
    );
    toml = CodexTomlMerge.preserveManagedTables(
      existingToml: existingToml,
      composedToml: toml,
    );
    toml = CodexTomlMerge.stripInvalidHookTypes(toml);

    final error = _generator.validateCodexToml(toml);
    if (error != null) {
      throw CodexHomeProvisionException(
        'Codex config.toml invalid for ${provider.id}: $error',
      );
    }

    // Fail fast on hook types the Codex CLI cannot parse — an unknown variant
    // (e.g. `http`) makes codex refuse to load the entire config at startup.
    final invalidHookTypes = CodexTomlParser.invalidHookTypes(toml);
    if (invalidHookTypes.isNotEmpty) {
      throw CodexHomeProvisionException(
        'Codex config.toml has unsupported hook type(s) for ${provider.id}: '
        '${invalidHookTypes.join(', ')} (allowed: '
        '${CodexTomlParser.allowedHookTypes.join(', ')})',
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
      final sidecarDir = providerDir?.trim();
      if (sidecarDir != null && sidecarDir.isNotEmpty) {
        await CodexConfigSidecar.copyIntoCodexHome(
          fs: store,
          providerDir: sidecarDir,
          codexHome: codexHome,
          configToml: toml,
        );
      }
    }
  }
}

final class CodexHomeProvisionException implements Exception {
  CodexHomeProvisionException(this.message);

  final String message;

  @override
  String toString() => message;
}
