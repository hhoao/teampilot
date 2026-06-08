import 'dart:convert';
import 'dart:io';

import '../../../models/claude_credential_link_result.dart';
import '../../cli/cli_invocation.dart';
import '../../io/filesystem.dart';
import '../../session/launch_command_builder.dart';
import 'codex_auth_artifacts.dart';

typedef CodexCredentialProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class CodexProviderCredentialsService {
  CodexProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.codexExecutable = 'codex',
    String? Function()? resolveCodexExecutable,
    CodexCredentialProcessRunner? processRunner,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveCodexExecutable = resolveCodexExecutable,
       _processRunner = processRunner ?? _defaultProcessRunner;

  final Filesystem _fs;
  final String _basePath;
  final String codexExecutable;
  final String? Function()? _resolveCodexExecutable;
  final CodexCredentialProcessRunner _processRunner;

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    return Process.run(
      executable,
      arguments,
      environment: environment,
    );
  }

  String providerDir(String providerId) => _fs.pathContext.join(
    _basePath,
    'providers',
    'codex',
    providerId.trim(),
  );

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

  Future<bool> importFromGlobal(
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

  Future<bool> importFromFile(
    String providerId,
    String sourcePath, {
    bool replace = false,
  }) async {
    return _importCopy(providerId, sourcePath, replace: replace);
  }

  Future<bool> _importCopy(
    String providerId,
    String src, {
    required bool replace,
  }) async {
    final srcStat = await _fs.stat(src);
    if (!srcStat.isFile) return false;
    final dest = credentialPath(providerId);
    if (!replace && (await _fs.stat(dest)).isFile) return false;
    await _fs.ensureDir(providerDir(providerId));
    final bytes = await _fs.readBytes(src);
    if (bytes == null) return false;
    if (!CodexAuthArtifacts.authJsonIndicatesReady(utf8.decode(bytes))) {
      return false;
    }
    await _fs.writeBytes(dest, bytes);
    return (await probe(providerId)).isReady;
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

  Future<ProcessResult> _runCodex(
    List<String> subcommand, {
    required String providerId,
    Map<String, String> platformEnv = const {},
  }) async {
    final executable = _resolvedCodexExecutable();
    final invocation = CliInvocation.fromExecutable(executable);
    final env = {
      ...platformEnv,
      ...loginEnvironment(providerId, useWslPaths: invocation.usesWsl),
    };
    final launch = CliInvocation.resolveProcessLaunch(
      executable: executable,
      subcommand: subcommand,
      environment: env,
    );
    return _processRunner(
      launch.executable,
      launch.arguments,
      environment: launch.environment,
    );
  }

  Future<bool> runAuthLogin(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
    await _fs.ensureDir(providerDir(providerId));
    try {
      final result = await _runCodex(
        const ['login'],
        providerId: providerId,
        platformEnv: platformEnv,
      );
      return result.exitCode == 0 && (await probe(providerId)).isReady;
    } on ProcessException {
      return false;
    }
  }

  Future<bool> revokeCredentials(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
    if (!(await probe(providerId)).isReady) return false;
    try {
      final result = await _runCodex(
        const ['logout'],
        providerId: providerId,
        platformEnv: platformEnv,
      );
      if (result.exitCode != 0) return false;
    } on ProcessException {
      return false;
    }
    final path = credentialPath(providerId);
    if ((await _fs.stat(path)).exists) {
      await _fs.removeRecursive(path);
    }
    return !(await probe(providerId)).isReady;
  }

  Future<String?> _readText(String path) async {
    final text = await _fs.readString(path);
    if (text != null) return text;
    final bytes = await _fs.readBytes(path);
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }
}
