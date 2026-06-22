import 'dart:convert';
import 'dart:io';

import '../../../models/claude_credential_link_result.dart';
import '../../../models/credential_action_result.dart';
import '../../cli/cli_invocation.dart';
import '../../io/filesystem.dart';
import '../../session/launch_command_builder.dart';
import '../credential_binding.dart';
import '../credential_process_result.dart';

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
    String? Function()? resolveHomeDirectory,
    ClaudeCredentialProcessRunner? processRunner,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveClaudeExecutable = resolveClaudeExecutable,
       _resolveHomeDirectory = resolveHomeDirectory,
       _processRunner = processRunner ?? _defaultProcessRunner;

  static const credentialsFileName = '.credentials.json';

  final Filesystem _fs;
  final String _basePath;
  final String claudeExecutable;
  final String? Function()? _resolveClaudeExecutable;
  final String? Function()? _resolveHomeDirectory;
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

  String globalCredentialPath(String homeDirectory) =>
      globalClaudeCredentialPath(homeDirectory, _fs.pathContext);

  String globalClaudeConfigDir(String homeDirectory) =>
      _fs.pathContext.join(homeDirectory.trim(), '.claude');

  String _resolvedHome([String? homeDirectory]) {
    final explicit = homeDirectory?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return _resolveHomeDirectory?.call()?.trim() ?? '';
  }

  String effectiveCredentialPath(
    String providerId, {
    CredentialBindingKind binding = CredentialBindingKind.linked,
    String? homeDirectory,
  }) {
    final home = _resolvedHome(homeDirectory);
    if (binding == CredentialBindingKind.linked && home.isNotEmpty) {
      return globalCredentialPath(home);
    }
    return credentialPath(providerId);
  }

  Future<CredentialProbe> probe(
    String providerId, {
    CredentialBindingKind binding = CredentialBindingKind.linked,
    String? homeDirectory,
  }) async {
    final path = effectiveCredentialPath(
      providerId,
      binding: binding,
      homeDirectory: homeDirectory,
    );
    final stat = await _fs.stat(path);
    final ready = await _credentialExistsAt(path);
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
    CredentialBindingKind binding = CredentialBindingKind.linked,
  }) async {
    if (binding == CredentialBindingKind.linked) {
      return materializeLinkedBinding(
        providerId,
        homeDirectory: homeDirectory,
        replace: replace,
      );
    }
    final src = globalCredentialPath(homeDirectory);
    return _importCopy(providerId, src, replace: replace);
  }

  Future<CredentialActionResult> importFromFile(
    String providerId,
    String sourcePath, {
    bool replace = false,
  }) async {
    return _importCopy(
      providerId,
      sourcePath,
      replace: replace,
      binding: CredentialBindingKind.isolated,
    );
  }

  Future<CredentialActionResult> materializeLinkedBinding(
    String providerId, {
    required String homeDirectory,
    bool replace = true,
  }) async {
    final global = globalCredentialPath(homeDirectory);
    if (!(await _credentialExistsAt(global))) {
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.sourceMissing,
          path: global,
        ),
      );
    }
    await _fs.ensureDir(providerDir(providerId));
    final dest = credentialPath(providerId);
    final destStat = await _fs.stat(dest);
    if (destStat.isSymlink) {
      return CredentialActionResult.success;
    }
    if (destStat.exists && !replace) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.destinationExists,
        ),
      );
    }
    if (destStat.exists) {
      await _fs.removeRecursive(dest);
    }
    if (await _fs.createSymlink(target: global, linkPath: dest)) {
      return CredentialActionResult.success;
    }
    return CredentialActionResult.failure(
      const CredentialActionFailure(
        code: CredentialActionFailureCode.verifyFailed,
      ),
    );
  }

  Future<CredentialActionResult> _importCopy(
    String providerId,
    String src, {
    required bool replace,
    CredentialBindingKind binding = CredentialBindingKind.isolated,
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
    final destStat = await _fs.stat(dest);
    if (!replace && await _credentialExistsAt(dest)) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.destinationExists,
        ),
      );
    }
    if (destStat.exists) {
      await _fs.removeRecursive(dest);
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
    if (!_validateCredentialBytes(bytes)) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.invalidCredential,
        ),
      );
    }
    await _fs.writeBytes(dest, bytes);
    if (!(await probe(providerId, binding: binding)).isReady) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.verifyFailed,
        ),
      );
    }
    return CredentialActionResult.success;
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
    String providerId, {
    CredentialBindingKind binding = CredentialBindingKind.linked,
    String? homeDirectory,
  }) async {
    final home = _resolvedHome(homeDirectory);
    if (binding == CredentialBindingKind.linked && home.isNotEmpty) {
      final materialize = await materializeLinkedBinding(
        providerId,
        homeDirectory: home,
        replace: true,
      );
      if (!materialize.ok) {
        return CredentialLinkResult.missing;
      }
    }

    final sessionPath = _fs.pathContext.join(
      sessionClaudeDir,
      credentialsFileName,
    );
    final src = effectiveCredentialPath(
      providerId,
      binding: binding,
      homeDirectory: home,
    );
    if (!(await _credentialExistsAt(src))) {
      return CredentialLinkResult.missing;
    }

    final sessionStat = await _fs.stat(sessionPath);
    if (sessionStat.isFile || sessionStat.isSymlink) {
      if (!await _sessionCredentialNeedsRelink(sessionPath, src)) {
        return CredentialLinkResult.alreadyPresent;
      }
      await _fs.removeRecursive(sessionPath);
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

  Future<bool> _credentialExistsAt(String path) async {
    final stat = await _fs.stat(path);
    if (stat.isFile) return true;
    if (!stat.isSymlink) return false;
    final target = await _fs.readSymlinkTarget(path);
    if (target == null || target.trim().isEmpty) return false;
    return (await _fs.stat(target)).isFile;
  }

  Future<bool> _sessionCredentialNeedsRelink(
    String sessionPath,
    String srcPath,
  ) async {
    final sessionStat = await _fs.stat(sessionPath);
    if (!sessionStat.isFile && !sessionStat.isSymlink) return true;
    if (sessionStat.isSymlink) {
      final target = await _fs.readSymlinkTarget(sessionPath);
      return target != srcPath;
    }
    final srcStat = await _fs.stat(srcPath);
    if (!srcStat.isFile && !srcStat.isSymlink) return true;
    final sessionMtime = sessionStat.mtime;
    final srcMtime = srcStat.mtime;
    if (sessionMtime == null || srcMtime == null) return false;
    return srcMtime.isAfter(sessionMtime);
  }

  Map<String, String> loginEnvironment(
    String providerId, {
    bool useWslPaths = false,
    CredentialBindingKind binding = CredentialBindingKind.linked,
    String? homeDirectory,
  }) {
    final home = _resolvedHome(homeDirectory);
    var configDir = binding == CredentialBindingKind.linked && home.isNotEmpty
        ? globalClaudeConfigDir(home)
        : providerDir(providerId);
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
    CredentialBindingKind binding = CredentialBindingKind.linked,
    String? homeDirectory,
  }) async {
    final executable = _resolvedClaudeExecutable();
    final invocation = CliInvocation.fromExecutable(executable);
    final env = {
      ...platformEnv,
      ...loginEnvironment(
        providerId,
        useWslPaths: invocation.usesWsl,
        binding: binding,
        homeDirectory: homeDirectory,
      ),
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

  Future<CredentialActionResult> runAuthLogin(
    String providerId, {
    Map<String, String> platformEnv = const {},
    CredentialBindingKind binding = CredentialBindingKind.linked,
    String? homeDirectory,
  }) async {
    await _fs.ensureDir(providerDir(providerId));
    final executable = _resolvedClaudeExecutable();
    try {
      final result = await _runClaude(
        const ['auth', 'login'],
        providerId: providerId,
        platformEnv: platformEnv,
        binding: binding,
        homeDirectory: homeDirectory,
      );
      if (binding == CredentialBindingKind.linked) {
        final home = _resolvedHome(homeDirectory);
        if (home.isNotEmpty) {
          await materializeLinkedBinding(
            providerId,
            homeDirectory: home,
            replace: true,
          );
        }
      }
      return loginCommandResult(
        result: result,
        ready: (await probe(
          providerId,
          binding: binding,
          homeDirectory: homeDirectory,
        )).isReady,
        executable: executable,
      );
    } on ProcessException {
      return loginProcessError(executable);
    }
  }

  Future<CredentialActionResult> revokeCredentials(
    String providerId, {
    Map<String, String> platformEnv = const {},
    CredentialBindingKind binding = CredentialBindingKind.linked,
    String? homeDirectory,
  }) async {
    if (!(await probe(
      providerId,
      binding: binding,
      homeDirectory: homeDirectory,
    )).isReady) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.revokeFailed,
        ),
      );
    }
    final executable = _resolvedClaudeExecutable();
    try {
      final result = await _runClaude(
        const ['auth', 'logout'],
        providerId: providerId,
        platformEnv: platformEnv,
        binding: binding,
        homeDirectory: homeDirectory,
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
    if (binding == CredentialBindingKind.linked) {
      final linkPath = credentialPath(providerId);
      if ((await _fs.stat(linkPath)).isSymlink) {
        await _fs.removeRecursive(linkPath);
      }
    } else {
      final path = credentialPath(providerId);
      if ((await _fs.stat(path)).exists) {
        await _fs.removeRecursive(path);
      }
    }
    return revokeVerifyResult(!(await probe(
      providerId,
      binding: binding,
      homeDirectory: homeDirectory,
    )).isReady);
  }
}
