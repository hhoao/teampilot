import 'dart:convert';
import 'dart:io';

import '../../../models/claude_credential_link_result.dart';
import '../../../models/credential_action_result.dart';
import '../../host/host_one_shot_runner.dart';
import '../../io/filesystem.dart';
import '../../session/launch_command_builder.dart';
import '../credential_host_request.dart';
import '../credential_process_result.dart';
import '../provider_credential_host_runner.dart';
import 'opencode_auth_artifacts.dart';
import 'opencode_data_layout.dart';

class OpencodeProviderCredentialsService {
  OpencodeProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.opencodeExecutable = 'opencode',
    String? Function()? resolveOpencodeExecutable,
    ProviderCredentialHostRunner? hostRunner,
    OpencodeDataLayout? layout,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveOpencodeExecutable = resolveOpencodeExecutable,
       _hostRunner = hostRunner,
       _layout = layout ?? const OpencodeDataLayout();

  final Filesystem _fs;
  final String _basePath;
  final String opencodeExecutable;
  final String? Function()? _resolveOpencodeExecutable;
  final ProviderCredentialHostRunner? _hostRunner;
  final OpencodeDataLayout _layout;

  String providerDir(String providerId) => _fs.pathContext.join(
    _basePath,
    'providers',
    'opencode',
    providerId.trim(),
  );

  String credentialPath(String providerId) =>
      _layout.providerAuthJsonPath(providerDir(providerId));

  Future<CredentialProbe> probe(String providerId) async {
    final path = credentialPath(providerId);
    final stat = await _fs.stat(path);
    if (!stat.isFile) {
      return CredentialProbe(
        providerId: providerId,
        status: CredentialStatus.missing,
        credentialPath: path,
      );
    }
    final content = await _readText(path);
    final ready = OpencodeAuthArtifacts.authJsonIndicatesReady(
      content,
      providerId,
    );
    return CredentialProbe(
      providerId: providerId,
      status: ready ? CredentialStatus.ready : CredentialStatus.missing,
      credentialPath: path,
      updatedAt: stat.mtime,
    );
  }

  Future<CredentialActionResult> importFromGlobal(
    String providerId, {
    required String homeDirectory,
    bool replace = false,
    Map<String, String> platformEnv = const {},
  }) async {
    final src = _layout.authJsonPath(
      _layout.globalDataHome(homeDirectory, platformEnv: platformEnv),
    );
    return importFromFile(providerId, src, replace: replace);
  }

  Future<CredentialActionResult> importFromFile(
    String providerId,
    String sourcePath, {
    bool replace = false,
  }) async {
    final srcStat = await _fs.stat(sourcePath);
    if (!srcStat.isFile) {
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.sourceMissing,
          path: sourcePath,
        ),
      );
    }
    final raw = await _readText(sourcePath);
    if (raw == null) {
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.sourceUnreadable,
          path: sourcePath,
        ),
      );
    }
    final entry = _extractProviderEntry(raw, providerId);
    if (entry == null) {
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.providerEntryMissing,
          path: sourcePath,
          providerId: providerId,
          availableProviderIds: _providerKeysInAuth(raw),
        ),
      );
    }
    return _writeProviderEntry(providerId, entry, replace: replace);
  }

  Map<String, Object?>? _extractProviderEntry(String raw, String providerId) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, Object?>();
      final entry = map[providerId];
      if (entry is Map) return entry.cast<String, Object?>();
      if (map.containsKey('type')) return map;
      return null;
    } on Object {
      return null;
    }
  }

  List<String> _providerKeysInAuth(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      return decoded.keys
          .map((key) => key.toString().trim())
          .where((key) => key.isNotEmpty && key != 'version')
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<CredentialActionResult> _writeProviderEntry(
    String providerId,
    Map<String, Object?> entry, {
    required bool replace,
  }) async {
    if (!OpencodeAuthArtifacts.entryIndicatesReady({
      providerId: entry,
    }, providerId)) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.invalidCredential,
        ),
      );
    }
    final dest = credentialPath(providerId);
    if (!replace && (await _fs.stat(dest)).isFile) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.destinationExists,
        ),
      );
    }
    await _fs.ensureDir(_layout.providerDataHome(providerDir(providerId)));
    final payload = <String, Object?>{providerId: entry};
    await _fs.atomicWrite(
      dest,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    if (!(await probe(providerId)).isReady) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.verifyFailed,
        ),
      );
    }
    return CredentialActionResult.success;
  }

  Future<String?> readAuthContentForLaunch(String providerId) async {
    final path = credentialPath(providerId);
    if (!(await _fs.stat(path)).isFile) return null;
    final content = await _readText(path);
    if (content == null || content.trim().isEmpty) return null;
    if (!OpencodeAuthArtifacts.authJsonIndicatesReady(content, providerId)) {
      return null;
    }
    return content.trim();
  }

  Map<String, String> loginEnvironment(
    String providerId, {
    bool useWslPaths = false,
  }) {
    var xdgDataHome = _layout.providerXdgDataHome(providerDir(providerId));
    if (useWslPaths) {
      xdgDataHome = LaunchCommandBuilder.normalizePathForCli(
        xdgDataHome,
        useWslPaths: true,
      );
    }
    return {'XDG_DATA_HOME': xdgDataHome};
  }

  String _resolvedOpencodeExecutable() {
    final resolved = _resolveOpencodeExecutable?.call()?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return opencodeExecutable;
  }

  ProviderCredentialHostRunner get _runner =>
      _hostRunner ?? ProviderCredentialHostRunner.forAppStorage();

  Future<HostRunResult> _runOpencode(
    List<String> subcommand, {
    required String providerId,
    required bool login,
    Map<String, String> platformEnv = const {},
  }) async {
    final preferencePath = _resolvedOpencodeExecutable();
    final request = CredentialHostRequest.build(
      preferencePath: preferencePath,
      subcommand: subcommand,
      environment: {
        ...platformEnv,
        ...loginEnvironment(
          providerId,
          useWslPaths: CredentialHostRequest.usePosixCliPaths(preferencePath),
        ),
      },
    );
    final runner = _runner;
    return login ? runner.runLogin(request) : runner.run(request);
  }

  Future<CredentialActionResult> runAuthLogin(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
    await _fs.ensureDir(_layout.providerDataHome(providerDir(providerId)));
    if (!(await probe(providerId)).isReady) {
      await _removeCredentialFileIfPresent(providerId);
    }
    final executable = _resolvedOpencodeExecutable();
    try {
      final result = await _runOpencode(
        ['providers', 'login', '-p', providerId],
        providerId: providerId,
        platformEnv: platformEnv,
        login: true,
      );
      return loginCommandResult(
        hostResult: result,
        ready: (await probe(providerId)).isReady,
        executable: executable,
        clearIncompleteCredentials: () =>
            _removeCredentialFileIfPresent(providerId),
      );
    } on ProcessException {
      await _removeCredentialFileIfPresent(providerId);
      return loginProcessError(executable);
    }
  }

  Future<CredentialActionResult> revokeCredentials(String providerId) async {
    final ready = (await probe(providerId)).isReady;
    if (!ready) {
      final path = credentialPath(providerId);
      if (!(await _fs.stat(path)).isFile) {
        return CredentialActionResult.failure(
          const CredentialActionFailure(
            code: CredentialActionFailureCode.revokeFailed,
          ),
        );
      }
      await _removeCredentialFileIfPresent(providerId);
      return revokeVerifyResult(!(await probe(providerId)).isReady);
    }
    final path = credentialPath(providerId);
    if ((await _fs.stat(path)).exists) {
      await _fs.removeRecursive(path);
    }
    return revokeVerifyResult(!(await probe(providerId)).isReady);
  }

  Future<void> _removeCredentialFileIfPresent(String providerId) async {
    final path = credentialPath(providerId);
    if ((await _fs.stat(path)).exists) {
      await _fs.removeRecursive(path);
    }
  }

  Future<String?> _readText(String path) async {
    final text = await _fs.readString(path);
    if (text != null) return text;
    final bytes = await _fs.readBytes(path);
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }
}
