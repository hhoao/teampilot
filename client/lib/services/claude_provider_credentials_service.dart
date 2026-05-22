import 'dart:convert';
import 'dart:io';

import '../models/claude_credential_link_result.dart';
import 'io/filesystem.dart';

class ClaudeProviderCredentialsService {
  ClaudeProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.claudeExecutable = 'claude',
  }) : _fs = fs,
       _basePath = basePath.trim();

  static const credentialsFileName = '.credentials.json';

  final Filesystem _fs;
  final String _basePath;
  final String claudeExecutable;

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

  Map<String, String> loginEnvironment(String providerId) => {
    'CLAUDE_CONFIG_DIR': providerDir(providerId),
    'CCGUI_CLI_LOGIN_AUTHORIZED': '1',
  };

  Future<bool> runAuthLogin(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
    await _fs.ensureDir(providerDir(providerId));
    final result = await Process.run(
      claudeExecutable,
      ['auth', 'login'],
      environment: {...platformEnv, ...loginEnvironment(providerId)},
    );
    return result.exitCode == 0 && (await probe(providerId)).isReady;
  }

  Future<bool> revokeCredentials(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
    if (!(await probe(providerId)).isReady) return false;
    final result = await Process.run(
      claudeExecutable,
      ['auth', 'logout'],
      environment: {...platformEnv, ...loginEnvironment(providerId)},
    );
    if (result.exitCode != 0) return false;
    final path = credentialPath(providerId);
    if ((await _fs.stat(path)).exists) {
      await _fs.removeRecursive(path);
    }
    return !(await probe(providerId)).isReady;
  }
}
