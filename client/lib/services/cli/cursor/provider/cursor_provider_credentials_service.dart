import 'dart:convert';
import 'dart:io';

import '../../../../models/credential_probe.dart';
import '../../../../models/credential_link_result.dart';
import '../../../../models/credential_action_result.dart';
import '../../../host/host_one_shot_runner.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_host_request.dart';
import '../../../provider/credential_process_result.dart';
import '../../../provider/provider_credential_host_runner.dart';
import 'cursor_auth_artifacts.dart';
import 'cursor_cli_config_policy.dart';
import 'cursor_home_layout.dart';
import 'cursor_launch_environment.dart';

class CursorProviderCredentialsService {
  CursorProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.cursorExecutable = 'cursor-agent',
    String? Function()? resolveCursorExecutable,
    ProviderCredentialHostRunner? hostRunner,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveCursorExecutable = resolveCursorExecutable,
       _hostRunner = hostRunner;

  final Filesystem _fs;
  final String _basePath;
  final String cursorExecutable;
  final String? Function()? _resolveCursorExecutable;
  final ProviderCredentialHostRunner? _hostRunner;

  CursorHomeLayout get _layout =>
      CursorHomeLayout(pathContext: _fs.pathContext);

  String providerHome(String providerId) => _fs.pathContext.join(
    _basePath,
    'providers',
    'cursor',
    providerId.trim(),
    'home',
  );

  String providerCursorDir(String providerId) =>
      _layout.cursorDir(providerHome(providerId));

  Future<CredentialProbe> probe(String providerId) async {
    final home = providerHome(providerId);
    for (final authPath in _layout.authJsonCandidates(home)) {
      final authStat = await _fs.stat(authPath);
      if (!authStat.isFile) continue;
      final content = await _readText(authPath);
      final ready =
          content != null &&
          CursorAuthArtifacts.authJsonIndicatesLoggedIn(content);
      return CredentialProbe(
        providerId: providerId,
        status: ready ? CredentialStatus.ready : CredentialStatus.missing,
        credentialPath: authPath,
        updatedAt: authStat.mtime,
      );
    }
    final missingPath = _layout.authJson(home);
    return CredentialProbe(
      providerId: providerId,
      status: CredentialStatus.missing,
      credentialPath: missingPath,
    );
  }

  Future<CredentialActionResult> importFromGlobal(
    String providerId, {
    required String homeDirectory,
    Map<String, String> platformEnv = const {},
    bool replace = false,
  }) async {
    final globalAuth = await _resolveGlobalAuthPath(
      homeDirectory,
      platformEnv: platformEnv,
    );
    if (!(await _fs.stat(globalAuth)).isFile) {
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.requiredFileMissing,
          path: globalAuth,
        ),
      );
    }

    final cursorResult = await importFromCursorDirectory(
      providerId,
      _layout.cursorDir(homeDirectory),
      replace: replace,
    );
    if (!cursorResult.ok) return cursorResult;

    final destAuth = _layout.authJson(providerHome(providerId));
    final authCopied = await _copyFile(
      src: globalAuth,
      dest: destAuth,
      replace: replace,
      required: true,
    );
    if (!authCopied.ok) return authCopied;
    if (!(await probe(providerId)).isReady) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.verifyFailed,
        ),
      );
    }
    return CredentialActionResult.success;
  }

  Future<CredentialActionResult> importFromCursorDirectory(
    String providerId,
    String sourceCursorDir, {
    bool replace = false,
  }) async {
    final destCursorDir = providerCursorDir(providerId);
    for (final relativePath in CursorAuthArtifacts.cursorDirRequired) {
      final result = await _importCursorDirFile(
        sourceCursorDir: sourceCursorDir,
        destCursorDir: destCursorDir,
        relativePath: relativePath,
        replace: replace,
        required: _requiresSourceCursorDirFile(relativePath),
      );
      if (!result.ok) return result;
    }
    for (final relativePath in CursorAuthArtifacts.cursorDirOptional) {
      await _importCursorDirFile(
        sourceCursorDir: sourceCursorDir,
        destCursorDir: destCursorDir,
        relativePath: relativePath,
        replace: replace,
        required: false,
      );
    }
    await _ensureDefaultCliConfig(destCursorDir);
    return CredentialActionResult.success;
  }

  /// Imports `$HOME/.config/cursor/auth.json` from [sourceAuthJsonPath].
  Future<CredentialActionResult> importAuthJsonFile(
    String providerId,
    String sourceAuthJsonPath, {
    bool replace = false,
  }) async {
    final destAuth = _layout.authJson(providerHome(providerId));
    final copied = await _copyFile(
      src: sourceAuthJsonPath,
      dest: destAuth,
      replace: replace,
      required: true,
    );
    if (!copied.ok) return copied;
    if (!(await probe(providerId)).isReady) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.invalidCredential,
        ),
      );
    }
    return CredentialActionResult.success;
  }

  Future<CredentialActionResult> _importCursorDirFile({
    required String sourceCursorDir,
    required String destCursorDir,
    required String relativePath,
    required bool replace,
    required bool required,
  }) async {
    final src = _fs.pathContext.join(sourceCursorDir, relativePath);
    final dest = _fs.pathContext.join(destCursorDir, relativePath);
    return _copyFile(
      src: src,
      dest: dest,
      replace: replace,
      required: required,
    );
  }

  Future<CredentialActionResult> _copyFile({
    required String src,
    required String dest,
    required bool replace,
    required bool required,
  }) async {
    final srcStat = await _fs.stat(src);
    if (!srcStat.isFile) {
      if (!required) return CredentialActionResult.success;
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.requiredFileMissing,
          path: src,
        ),
      );
    }

    if (!replace && (await _fs.stat(dest)).isFile) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.destinationExists,
        ),
      );
    }

    await _fs.ensureDir(_fs.pathContext.dirname(dest));
    final bytes = await _fs.readBytes(src);
    if (bytes == null) {
      if (!required) return CredentialActionResult.success;
      return CredentialActionResult.failure(
        CredentialActionFailure(
          code: CredentialActionFailureCode.sourceUnreadable,
          path: src,
        ),
      );
    }
    await _fs.writeBytes(dest, bytes);
    return CredentialActionResult.success;
  }

  Future<CredentialLinkResult> syncAuthToMemberHome(
    String providerId,
    String memberHome,
  ) async {
    if (!(await probe(providerId)).isReady) {
      return CredentialLinkResult.missing;
    }

    final providerHomePath = providerHome(providerId);
    final srcCursorDir = _layout.cursorDir(providerHomePath);
    final destCursorDir = _layout.cursorDir(memberHome);

    var allAlreadyPresent = true;
    var anyLinked = false;
    var anyCopied = false;

    void applyOutcome(_MemberAuthSyncOutcome outcome) {
      switch (outcome) {
        case _MemberAuthSyncOutcome.alreadyPresent:
          return;
        case _MemberAuthSyncOutcome.linked:
          allAlreadyPresent = false;
          anyLinked = true;
        case _MemberAuthSyncOutcome.copied:
          allAlreadyPresent = false;
          anyCopied = true;
      }
    }

    for (final relativePath in await _cursorDirAuthFilesPresentAt(
      srcCursorDir,
    )) {
      final src = _fs.pathContext.join(srcCursorDir, relativePath);
      final dest = _fs.pathContext.join(destCursorDir, relativePath);
      if (!(await _fs.stat(src)).isFile) continue;

      if (relativePath == CursorHomeLayout.cliConfigFileName) {
        applyOutcome(await _syncCliConfigToMemberHome(src: src, dest: dest));
        continue;
      }

      // Session-local optional files (tip flag, statsig cache): never overwrite.
      final destStat = await _fs.stat(dest);
      if (destStat.isFile || destStat.isSymlink) continue;

      allAlreadyPresent = false;
      await _fs.ensureDir(_fs.pathContext.dirname(dest));
      if (await _fs.createSymlink(target: src, linkPath: dest)) {
        anyLinked = true;
        continue;
      }
      final bytes = await _fs.readBytes(src);
      if (bytes == null) continue;
      await _fs.writeBytes(dest, bytes);
      anyCopied = true;
    }

    applyOutcome(
      await _syncAuthJsonToMemberHome(
        src: _layout.authJson(providerHomePath),
        dest: _layout.authJson(memberHome),
      ),
    );

    if (allAlreadyPresent) return CredentialLinkResult.alreadyPresent;
    if (anyLinked) return CredentialLinkResult.linked;
    if (anyCopied) return CredentialLinkResult.copied;
    return CredentialLinkResult.missing;
  }

  Future<_MemberAuthSyncOutcome> _syncCliConfigToMemberHome({
    required String src,
    required String dest,
  }) async {
    final destLstat = await _fs.lstat(dest);
    if (destLstat.isSymlink) {
      final target = await _fs.readSymlinkTarget(dest);
      if (target != null &&
          _fs.pathContext.normalize(target) ==
              _fs.pathContext.normalize(src)) {
        return _MemberAuthSyncOutcome.alreadyPresent;
      }
      await _fs.removeRecursive(dest);
      await _fs.ensureDir(_fs.pathContext.dirname(dest));
      if (await _fs.createSymlink(target: src, linkPath: dest)) {
        return _MemberAuthSyncOutcome.linked;
      }
      return _copyAuthArtifact(src: src, dest: dest);
    }

    if (!destLstat.isFile) {
      await _fs.ensureDir(_fs.pathContext.dirname(dest));
      if (await _fs.createSymlink(target: src, linkPath: dest)) {
        return _MemberAuthSyncOutcome.linked;
      }
      return _copyAuthArtifact(src: src, dest: dest);
    }

    // Overlay writes replace the provider symlink with a regular file. Merge
    // authInfo so a provider switch does not wipe permissions / model stamps.
    final srcRaw = await _readText(src);
    if (srcRaw == null) return _MemberAuthSyncOutcome.alreadyPresent;
    final destRaw = await _readText(dest) ?? '';
    if (CursorAuthArtifacts.cliConfigAuthInfoEqual(srcRaw, destRaw)) {
      return _MemberAuthSyncOutcome.alreadyPresent;
    }
    final destJson =
        CursorCliConfigPolicy.parseConfigJson(destRaw) ?? <String, Object?>{};
    final srcJson = CursorCliConfigPolicy.parseConfigJson(srcRaw) ?? const {};
    destJson['authInfo'] = srcJson['authInfo'];
    await _fs.ensureDir(_fs.pathContext.dirname(dest));
    await _fs.atomicWrite(
      dest,
      const JsonEncoder.withIndent('  ').convert(destJson),
    );
    return _MemberAuthSyncOutcome.copied;
  }

  Future<_MemberAuthSyncOutcome> _syncAuthJsonToMemberHome({
    required String src,
    required String dest,
  }) async {
    final destStat = await _fs.stat(dest);
    if (destStat.isFile) {
      final srcRaw = await _readText(src);
      final destRaw = await _readText(dest);
      if (srcRaw != null &&
          destRaw != null &&
          CursorAuthArtifacts.authJsonTokensEqual(srcRaw, destRaw)) {
        return _MemberAuthSyncOutcome.alreadyPresent;
      }
    }
    return _copyAuthArtifact(src: src, dest: dest);
  }

  Future<_MemberAuthSyncOutcome> _copyAuthArtifact({
    required String src,
    required String dest,
  }) async {
    final copied = await _copyFile(
      src: src,
      dest: dest,
      replace: true,
      required: true,
    );
    return copied.ok
        ? _MemberAuthSyncOutcome.copied
        : _MemberAuthSyncOutcome.alreadyPresent;
  }

  Future<String> _resolveGlobalAuthPath(
    String homeDirectory, {
    Map<String, String> platformEnv = const {},
  }) async {
    for (final candidate in _layout.globalAuthJsonCandidates(
      homeDirectory,
      platformEnv: platformEnv,
    )) {
      if ((await _fs.stat(candidate)).isFile) return candidate;
    }
    final candidates = _layout.globalAuthJsonCandidates(
      homeDirectory,
      platformEnv: platformEnv,
    );
    return candidates.isEmpty
        ? _layout.authJson(homeDirectory)
        : candidates.first;
  }

  Future<String?> _readText(String path) async {
    final text = await _fs.readString(path);
    if (text != null) return text;
    final bytes = await _fs.readBytes(path);
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  Future<List<String>> _cursorDirAuthFilesPresentAt(String cursorDir) async {
    final paths = <String>[
      ...CursorAuthArtifacts.cursorDirRequired,
      ...CursorAuthArtifacts.cursorDirOptional,
    ];
    final present = <String>[];
    for (final relativePath in paths) {
      if (CursorAuthArtifacts.isBusGenerated(relativePath)) continue;
      final path = _fs.pathContext.join(cursorDir, relativePath);
      if ((await _fs.stat(path)).isFile) {
        present.add(relativePath);
      }
    }
    return present;
  }

  Map<String, String> loginEnvironment(
    String providerId, {
    bool useWslPaths = false,
  }) {
    return CursorLaunchEnvironment.forMixed(
      homeRoot: providerHome(providerId),
      useWslPaths: useWslPaths,
    );
  }

  String _resolvedCursorExecutable() {
    final resolved = _resolveCursorExecutable?.call()?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return cursorExecutable;
  }

  ProviderCredentialHostRunner get _runner =>
      _hostRunner ?? ProviderCredentialHostRunner.forAppStorage();

  Future<HostRunResult> _runCursor(
    List<String> subcommand, {
    required String providerId,
    required bool login,
    Map<String, String> platformEnv = const {},
  }) async {
    final preferencePath = _resolvedCursorExecutable();
    final request = CredentialHostRequest.build(
      preferencePath: preferencePath,
      subcommand: subcommand,
      environment: {
        ...platformEnv,
        ...loginEnvironment(
          providerId,
          useWslPaths: CredentialHostRequest.usePosixCliPaths(preferencePath),
        ),
        // Print login URL instead of opening a browser on the remote/WSL host.
        if (login) 'NO_OPEN_BROWSER': '1',
      },
    );
    final runner = _runner;
    return login ? runner.runLogin(request) : runner.run(request);
  }

  Future<CredentialActionResult> runAuthLogin(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
    final home = providerHome(providerId);
    await _fs.ensureDir(home);
    await _ensureDefaultCliConfig(_layout.cursorDir(home));
    if (!(await probe(providerId)).isReady &&
        await _hasAuthArtifacts(providerId)) {
      await _removeAuthArtifacts(providerId);
    }
    final executable = _resolvedCursorExecutable();
    try {
      final result = await _runCursor(
        const ['login'],
        providerId: providerId,
        platformEnv: platformEnv,
        login: true,
      );
      return loginCommandResult(
        hostResult: result,
        ready: (await probe(providerId)).isReady,
        executable: executable,
        clearIncompleteCredentials: () => _removeAuthArtifacts(providerId),
      );
    } on ProcessException {
      await _removeAuthArtifacts(providerId);
      return loginProcessError(executable);
    }
  }

  Future<CredentialActionResult> revokeCredentials(
    String providerId, {
    Map<String, String> platformEnv = const {},
  }) async {
    final ready = (await probe(providerId)).isReady;
    if (!ready) {
      if (!await _hasAuthArtifacts(providerId)) {
        return CredentialActionResult.failure(
          const CredentialActionFailure(
            code: CredentialActionFailureCode.revokeFailed,
          ),
        );
      }
      await _removeAuthArtifacts(providerId);
      return revokeVerifyResult(!(await probe(providerId)).isReady);
    }
    try {
      await _runCursor(
        const ['logout'],
        providerId: providerId,
        platformEnv: platformEnv,
        login: false,
      );
    } on ProcessException {
      // Optional logout; continue deleting local auth artifacts.
    }
    await _removeAuthArtifacts(providerId);
    return revokeVerifyResult(!(await probe(providerId)).isReady);
  }

  Future<bool> _hasAuthArtifacts(String providerId) async {
    final home = providerHome(providerId);
    final cursorDir = _layout.cursorDir(home);
    for (final relativePath in [
      ...CursorAuthArtifacts.cursorDirRequired,
      ...CursorAuthArtifacts.cursorDirOptional,
    ]) {
      final path = _fs.pathContext.join(cursorDir, relativePath);
      if ((await _fs.stat(path)).isFile) return true;
    }
    return (await _fs.stat(_layout.authJson(home))).isFile;
  }

  bool _requiresSourceCursorDirFile(String relativePath) =>
      relativePath != CursorHomeLayout.cliConfigFileName;

  Future<void> _ensureDefaultCliConfig(String cursorDir) async {
    final path = _fs.pathContext.join(
      cursorDir,
      CursorHomeLayout.cliConfigFileName,
    );
    if ((await _fs.stat(path)).isFile) return;
    await _fs.ensureDir(cursorDir);
    await _fs.writeString(
      path,
      jsonEncode(_defaultCliConfig()),
    );
  }

  Map<String, Object?> _defaultCliConfig() => {
    'version': CursorCliConfigPolicy.defaultVersion,
    'permissions': <String, Object?>{
      'allow': <String>[],
      'deny': <String>[],
    },
  };

  Future<void> _removeAuthArtifacts(String providerId) async {
    final home = providerHome(providerId);
    final cursorDir = _layout.cursorDir(home);
    for (final relativePath in [
      ...CursorAuthArtifacts.cursorDirRequired,
      ...CursorAuthArtifacts.cursorDirOptional,
    ]) {
      final path = _fs.pathContext.join(cursorDir, relativePath);
      if ((await _fs.stat(path)).exists) {
        await _fs.removeRecursive(path);
      }
    }
    final authPath = _layout.authJson(home);
    if ((await _fs.stat(authPath)).exists) {
      await _fs.removeRecursive(authPath);
    }
    if (Platform.isMacOS) {
      final legacy = _fs.pathContext.join(
        _layout.configCursorDir(home),
        CursorHomeLayout.authFileName,
      );
      if (legacy != authPath && (await _fs.stat(legacy)).exists) {
        await _fs.removeRecursive(legacy);
      }
    }
  }
}

enum _MemberAuthSyncOutcome { alreadyPresent, linked, copied }
