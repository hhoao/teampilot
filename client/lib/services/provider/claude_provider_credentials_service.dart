import 'dart:convert';
import 'dart:io';

import '../../models/claude_credential_link_result.dart';
import '../cli/cli_invocation.dart';
import '../io/filesystem.dart';
import '../session/launch_command_builder.dart';

typedef ClaudeCredentialProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class ClaudeProviderCredentialsService {
  ClaudeProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.claudeExecutable = 'claude',
    String? Function()? resolveClaudeExecutable,
    ClaudeCredentialProcessRunner? processRunner,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveClaudeExecutable = resolveClaudeExecutable,
       _processRunner = processRunner ?? _defaultProcessRunner;

  static const credentialsFileName = '.credentials.json';

  final Filesystem _fs;
  final String _basePath;
  final String claudeExecutable;
  final String? Function()? _resolveClaudeExecutable;
  final ClaudeCredentialProcessRunner _processRunner;

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
    'claude',
    providerId.trim(),
  );

  String credentialPath(String providerId) =>
      _fs.pathContext.join(providerDir(providerId), credentialsFileName);

  Future<CredentialProbe> probe(String providerId) async {
    final path = credentialPath(providerId);
    final stat = await _fs.stat(path);
    return CredentialProbe(
      providerId: providerId,
      status: stat.isFile ? CredentialStatus.ready : CredentialStatus.missing,
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
      '.claude',
      credentialsFileName,
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
    await _fs.writeBytes(dest, bytes);
    return _validateCredentialBytes(bytes);
  }

  bool _validateCredentialBytes(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map && decoded.isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<CredentialLinkResult> ensureLinked(
    String sessionClaudeDir,
    String providerId,
  ) async {
    final sessionPath = _fs.pathContext.join(
      sessionClaudeDir,
      credentialsFileName,
    );
    final sessionStat = await _fs.stat(sessionPath);
    if (sessionStat.isFile || sessionStat.isSymlink) {
      return CredentialLinkResult.alreadyPresent;
    }
    final src = credentialPath(providerId);
    if (!(await _fs.stat(src)).isFile) {
      return CredentialLinkResult.missing;
    }
    await _fs.ensureDir(sessionClaudeDir);
    if (await _fs.createSymlink(target: src, linkPath: sessionPath)) {
      return CredentialLinkResult.linked;
    }
    final bytes = await _fs.readBytes(src);
    if (bytes == null) return CredentialLinkResult.missing;
    await _fs.writeBytes(sessionPath, bytes);
    return CredentialLinkResult.copied;
  }

  Map<String, String> loginEnvironment(
    String providerId, {
    bool useWslPaths = false,
  }) {
    var configDir = providerDir(providerId);
    if (useWslPaths) {
      configDir = LaunchCommandBuilder.normalizePathForCli(
        configDir,
        useWslPaths: true,
      );
    }
    return {
      'CLAUDE_CONFIG_DIR': configDir,
      'CCGUI_CLI_LOGIN_AUTHORIZED': '1',
    };
  }

  String _resolvedClaudeExecutable() {
    final resolved = _resolveClaudeExecutable?.call()?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return claudeExecutable;
  }

  Future<ProcessResult> _runClaude(
    List<String> subcommand, {
    required String providerId,
    Map<String, String> platformEnv = const {},
  }) async {
    final executable = _resolvedClaudeExecutable();
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
      final result = await _runClaude(
        const ['auth', 'login'],
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
      final result = await _runClaude(
        const ['auth', 'logout'],
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
}
