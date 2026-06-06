import 'dart:convert';
import 'dart:io';

import '../../../models/claude_credential_link_result.dart';
import '../../cli/cli_invocation.dart';
import '../../io/filesystem.dart';
import 'cursor_auth_artifacts.dart';
import 'cursor_home_layout.dart';
import 'cursor_launch_environment.dart';

typedef CursorCredentialProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class CursorProviderCredentialsService {
  CursorProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.cursorExecutable = 'cursor-agent',
    String? Function()? resolveCursorExecutable,
    CursorCredentialProcessRunner? processRunner,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveCursorExecutable = resolveCursorExecutable,
       _processRunner = processRunner ?? _defaultProcessRunner;

  static const _layout = CursorHomeLayout();

  final Filesystem _fs;
  final String _basePath;
  final String cursorExecutable;
  final String? Function()? _resolveCursorExecutable;
  final CursorCredentialProcessRunner _processRunner;

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
    final authPath = _layout.authJson(home);
    final authStat = await _fs.stat(authPath);
    if (!authStat.isFile) {
      return CredentialProbe(
        providerId: providerId,
        status: CredentialStatus.missing,
        credentialPath: authPath,
      );
    }
    final content = await _readText(authPath);
    final ready =
        content != null && CursorAuthArtifacts.authJsonIndicatesLoggedIn(content);
    return CredentialProbe(
      providerId: providerId,
      status: ready ? CredentialStatus.ready : CredentialStatus.missing,
      credentialPath: authPath,
      updatedAt: authStat.mtime,
    );
  }

  Future<bool> importFromGlobal(
    String providerId, {
    required String homeDirectory,
    bool replace = false,
  }) async {
    final okCursor = await importFromCursorDirectory(
      providerId,
      _layout.cursorDir(homeDirectory),
      replace: replace,
    );
    if (!okCursor) return false;

    final globalAuth = _layout.authJson(homeDirectory);
    final destAuth = _layout.authJson(providerHome(providerId));
    final authCopied = await _copyFile(
      src: globalAuth,
      dest: destAuth,
      replace: replace,
      required: true,
    );
    if (!authCopied) return false;
    return (await probe(providerId)).isReady;
  }

  Future<bool> importFromCursorDirectory(
    String providerId,
    String sourceCursorDir, {
    bool replace = false,
  }) async {
    final destCursorDir = providerCursorDir(providerId);
    for (final relativePath in CursorAuthArtifacts.cursorDirRequired) {
      final ok = await _importCursorDirFile(
        sourceCursorDir: sourceCursorDir,
        destCursorDir: destCursorDir,
        relativePath: relativePath,
        replace: replace,
        required: true,
      );
      if (!ok) return false;
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
    return true;
  }

  /// Imports `$HOME/.config/cursor/auth.json` from [sourceAuthJsonPath].
  Future<bool> importAuthJsonFile(
    String providerId,
    String sourceAuthJsonPath, {
    bool replace = false,
  }) async {
    final destAuth = _layout.authJson(providerHome(providerId));
    final ok = await _copyFile(
      src: sourceAuthJsonPath,
      dest: destAuth,
      replace: replace,
      required: true,
    );
    if (!ok) return false;
    return (await probe(providerId)).isReady;
  }

  Future<bool> _importCursorDirFile({
    required String sourceCursorDir,
    required String destCursorDir,
    required String relativePath,
    required bool replace,
    required bool required,
  }) async {
    final src = _fs.pathContext.join(sourceCursorDir, relativePath);
    final dest = _fs.pathContext.join(destCursorDir, relativePath);
    return _copyFile(src: src, dest: dest, replace: replace, required: required);
  }

  Future<bool> _copyFile({
    required String src,
    required String dest,
    required bool replace,
    required bool required,
  }) async {
    final srcStat = await _fs.stat(src);
    if (!srcStat.isFile) return !required;

    if (!replace && (await _fs.stat(dest)).isFile) return false;

    await _fs.ensureDir(_fs.pathContext.dirname(dest));
    final bytes = await _fs.readBytes(src);
    if (bytes == null) return !required;
    await _fs.writeBytes(dest, bytes);
    return true;
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

    for (final relativePath in await _cursorDirAuthFilesPresentAt(srcCursorDir)) {
      final dest = _fs.pathContext.join(destCursorDir, relativePath);
      final destStat = await _fs.stat(dest);
      if (destStat.isFile || destStat.isSymlink) continue;

      allAlreadyPresent = false;
      final src = _fs.pathContext.join(srcCursorDir, relativePath);
      if (!(await _fs.stat(src)).isFile) continue;

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

    final srcAuth = _layout.authJson(providerHomePath);
    final destAuth = _layout.authJson(memberHome);
    final destAuthStat = await _fs.stat(destAuth);
    if (!destAuthStat.isFile) {
      allAlreadyPresent = false;
      if (await _copyFile(
        src: srcAuth,
        dest: destAuth,
        replace: true,
        required: true,
      )) {
        anyCopied = true;
      }
    }

    if (allAlreadyPresent) return CredentialLinkResult.alreadyPresent;
    if (anyLinked) return CredentialLinkResult.linked;
    if (anyCopied) return CredentialLinkResult.copied;
    return CredentialLinkResult.missing;
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

  Future<ProcessResult> _runCursor(
    List<String> subcommand, {
    required String providerId,
    Map<String, String> platformEnv = const {},
  }) async {
    final executable = _resolvedCursorExecutable();
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
    await _fs.ensureDir(providerHome(providerId));
    try {
      final result = await _runCursor(
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
      await _runCursor(
        const ['logout'],
        providerId: providerId,
        platformEnv: platformEnv,
      );
    } on ProcessException {
      // Optional logout; continue deleting local auth artifacts.
    }
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
    return !(await probe(providerId)).isReady;
  }
}
