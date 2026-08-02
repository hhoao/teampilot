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
import 'codex_auth_artifacts.dart';

class CodexProviderCredentialsService {
  CodexProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.codexExecutable = 'codex',
    String? Function()? resolveCodexExecutable,
    ProviderCredentialHostRunner? hostRunner,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveCodexExecutable = resolveCodexExecutable,
       _hostRunner = hostRunner;

  final Filesystem _fs;
  final String _basePath;
  final String codexExecutable;
  final String? Function()? _resolveCodexExecutable;
  final ProviderCredentialHostRunner? _hostRunner;

  String providerDir(String providerId) =>
      _fs.pathContext.join(_basePath, 'providers', 'codex', providerId.trim());

  String credentialPath(String providerId) => _fs.pathContext.join(
    providerDir(providerId),
    CodexAuthArtifacts.authFileName,
  );

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
    final ready = CodexAuthArtifacts.authJsonIndicatesReady(content);
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
  }) async {
    final src = _fs.pathContext.join(
      homeDirectory,
      '.codex',
      CodexAuthArtifacts.authFileName,
    );
    return _importCopy(providerId, src, replace: replace);
  }

  Future<CredentialActionResult> importFromFile(
    String providerId,
    String sourcePath, {
    bool replace = false,
  }) async {
    return _importCopy(providerId, sourcePath, replace: replace);
  }

  Future<CredentialActionResult> _importCopy(
    String providerId,
    String src, {
    required bool replace,
  }) async {
    final srcStat = await _fs.stat(src);
    if (!srcStat.isFile) {
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.sourceMissing,
          path: src,
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
    await _fs.ensureDir(providerDir(providerId));
    final bytes = await _fs.readBytes(src);
    if (bytes == null) {
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.sourceUnreadable,
          path: src,
        ),
      );
    }
    if (!CodexAuthArtifacts.authJsonIndicatesReady(utf8.decode(bytes))) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.invalidCredential,
        ),
      );
    }
    await _fs.writeBytes(dest, bytes);
    if (!(await probe(providerId)).isReady) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.verifyFailed,
        ),
      );
    }
    return CredentialActionResult.success;
  }

  Map<String, String> loginEnvironment(
    String providerId, {
    bool useWslPaths = false,
  }) {
    var codexHome = providerDir(providerId);
    if (useWslPaths) {
      codexHome = LaunchCommandBuilder.normalizePathForCli(
        codexHome,
        useWslPaths: true,
      );
    }
    return {'CODEX_HOME': codexHome};
  }

  String _resolvedCodexExecutable() {
    final resolved = _resolveCodexExecutable?.call()?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return codexExecutable;
  }

  ProviderCredentialHostRunner get _runner =>
      _hostRunner ?? ProviderCredentialHostRunner.forAppStorage();

  Future<HostRunResult> _runCodex(
    List<String> subcommand, {
    required String providerId,
    required bool login,
    Map<String, String> platformEnv = const {},
  }) async {
    final preferencePath = _resolvedCodexExecutable();
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
    await _fs.ensureDir(providerDir(providerId));
    if (!(await probe(providerId)).isReady) {
      await _removeCredentialFileIfPresent(providerId);
    }
    final executable = _resolvedCodexExecutable();
    try {
      final result = await _runCodex(
        const ['login'],
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

  Future<CredentialActionResult> revokeCredentials(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
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
    final executable = _resolvedCodexExecutable();
    try {
      final result = await _runCodex(
        const ['logout'],
        providerId: providerId,
        platformEnv: platformEnv,
        login: false,
      );
      if (result.exitCode != 0) {
        return CredentialActionResult.failure(
          CredentialActionFailure(
            code: CredentialActionFailureCode.revokeFailed,
            exitCode: result.exitCode,
          ),
        );
      }
    } on ProcessException {
      return loginProcessError(executable);
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
