import 'dart:convert';
import 'dart:io';

import '../../../models/claude_credential_link_result.dart';
import '../../cli/cli_invocation.dart';
import '../../io/filesystem.dart';
import '../../session/launch_command_builder.dart';
import 'opencode_auth_artifacts.dart';
import 'opencode_data_layout.dart';

typedef OpencodeCredentialProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class OpencodeProviderCredentialsService {
  OpencodeProviderCredentialsService({
    required Filesystem fs,
    required String basePath,
    this.opencodeExecutable = 'opencode',
    String? Function()? resolveOpencodeExecutable,
    OpencodeCredentialProcessRunner? processRunner,
    OpencodeDataLayout? layout,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _resolveOpencodeExecutable = resolveOpencodeExecutable,
       _processRunner = processRunner ?? _defaultProcessRunner,
       _layout = layout ?? const OpencodeDataLayout();

  final Filesystem _fs;
  final String _basePath;
  final String opencodeExecutable;
  final String? Function()? _resolveOpencodeExecutable;
  final OpencodeCredentialProcessRunner _processRunner;
  final OpencodeDataLayout _layout;

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

  Future<bool> importFromGlobal(
    String providerId, {
    required String homeDirectory,
    bool replace = false,
  }) async {
    final src = _layout.authJsonPath(
      _layout.globalDataHome(homeDirectory),
    );
    return importFromFile(providerId, src, replace: replace);
  }

  Future<bool> importFromFile(
    String providerId,
    String sourcePath, {
    bool replace = false,
  }) async {
    final srcStat = await _fs.stat(sourcePath);
    if (!srcStat.isFile) return false;
    final raw = await _readText(sourcePath);
    if (raw == null) return false;
    final entry = _extractProviderEntry(raw, providerId);
    if (entry == null) return false;
    return _writeProviderEntry(
      providerId,
      entry,
      replace: replace,
    );
  }

  Map<String, Object?>? _extractProviderEntry(
    String raw,
    String providerId,
  ) {
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

  Future<bool> _writeProviderEntry(
    String providerId,
    Map<String, Object?> entry, {
    required bool replace,
  }) async {
    if (!OpencodeAuthArtifacts.entryIndicatesReady({providerId: entry}, providerId)) {
      return false;
    }
    final dest = credentialPath(providerId);
    if (!replace && (await _fs.stat(dest)).isFile) return false;
    await _fs.ensureDir(_layout.providerDataHome(providerDir(providerId)));
    final payload = <String, Object?>{providerId: entry};
    await _fs.atomicWrite(
      dest,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return (await probe(providerId)).isReady;
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

  Future<ProcessResult> _runOpencode(
    List<String> subcommand, {
    required String providerId,
    Map<String, String> platformEnv = const {},
  }) async {
    final executable = _resolvedOpencodeExecutable();
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
    await _fs.ensureDir(_layout.providerDataHome(providerDir(providerId)));
    try {
      final result = await _runOpencode(
        ['providers', 'login', '-p', providerId],
        providerId: providerId,
        platformEnv: platformEnv,
      );
      return result.exitCode == 0 && (await probe(providerId)).isReady;
    } on ProcessException {
      return false;
    }
  }

  Future<bool> revokeCredentials(String providerId) async {
    if (!(await probe(providerId)).isReady) return false;
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
