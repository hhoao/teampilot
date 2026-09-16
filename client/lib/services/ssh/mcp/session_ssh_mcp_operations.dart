import 'dart:async';
import 'dart:convert';

import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/ssh/ssh_storage_io.dart';

import 'session_ssh_mcp_constants.dart';
import 'session_ssh_mcp_paths.dart';
import 'session_ssh_mcp_targets.dart';

class SessionSshMcpToolResult {
  const SessionSshMcpToolResult.ok(this.text) : code = null;
  const SessionSshMcpToolResult.error(this.code, this.text);
  final String? code;
  final String text;
  bool get isError => code != null;
}

abstract class SessionSshMcpExecutor {
  Future<({int? exitCode, String stdout, String stderr})> runCommand({
    required SshProfile profile,
    required String command,
    required Duration timeout,
  });
  Future<void> upload({
    required SshProfile profile,
    required List<int> bytes,
    required String remotePath,
  });
  Future<List<int>> download({
    required SshProfile profile,
    required String remotePath,
  });
}

class SessionSshMcpContext {
  const SessionSshMcpContext({
    required this.enabled,
    required this.targets,
    required this.localAllowedRoots,
    required this.localUsesPosixPaths,
    required this.localFs,
  });
  final bool enabled;
  final List<SessionSshMcpTarget> targets;
  final List<String> localAllowedRoots;
  final bool localUsesPosixPaths;
  final Filesystem localFs;
}

class SessionSshMcpOperations {
  SessionSshMcpOperations({
    required SessionSshMcpExecutor executor,
    int maxOutputBytes = sessionSshMcpMaxOutputBytes,
  }) : _executor = executor,
       _maxOutputBytes = maxOutputBytes;

  final SessionSshMcpExecutor _executor;
  final int _maxOutputBytes;

  Future<SessionSshMcpToolResult> listServers(
    SessionSshMcpContext context, [
    Map<String, Object?> args = const {},
  ]) async {
    final disabled = _disabledResult(context);
    if (disabled != null) return disabled;

    return SessionSshMcpToolResult.ok(
      jsonEncode([
        for (final target in context.targets)
          {
            'profileId': target.profile.id,
            'name': target.profile.name,
            'host': target.profile.host,
            'port': target.profile.port,
            'username': target.profile.username,
            'folderPaths': target.folderPaths,
          },
      ]),
    );
  }

  Future<SessionSshMcpToolResult> executeCommand(
    SessionSshMcpContext context,
    Map<String, Object?> args,
  ) async {
    final disabled = _disabledResult(context);
    if (disabled != null) return disabled;

    final cmdString = _stringArg(args, 'cmdString')?.trim() ?? '';
    if (cmdString.isEmpty) {
      return const SessionSshMcpToolResult.error(
        sessionSshMcpErrorInvalidParams,
        'cmdString is required',
      );
    }

    final target = _resolveTarget(context, args);
    if (target == null) return _unknownTarget;

    final cwd = resolveSessionSshMcpRemoteCwd(
      cwd: _stringArg(args, 'cwd'),
      folderPaths: target.folderPaths,
    );
    if (cwd == null) return _pathError;

    final command = 'cd -- ${sessionSshMcpPosixQuote(cwd)} && $cmdString';
    try {
      final result = await _executor.runCommand(
        profile: target.profile,
        command: command,
        timeout: _timeoutOf(args),
      );
      final combined = '${result.stdout}${result.stderr}';
      final bytes = utf8.encode(combined);
      if (bytes.length > _maxOutputBytes) {
        return SessionSshMcpToolResult.error(
          sessionSshMcpErrorOutputLimit,
          utf8.decode(
            bytes.sublist(0, _maxOutputBytes),
            allowMalformed: true,
          ),
        );
      }
      return SessionSshMcpToolResult.ok(combined);
    } on TimeoutException {
      return const SessionSshMcpToolResult.error(
        sessionSshMcpErrorTimeout,
        'Command timed out',
      );
    } catch (error) {
      return SessionSshMcpToolResult.error(
        sessionSshMcpErrorUnavailable,
        _publicError(error),
      );
    }
  }

  Future<SessionSshMcpToolResult> upload(
    SessionSshMcpContext context,
    Map<String, Object?> args,
  ) async {
    final disabled = _disabledResult(context);
    if (disabled != null) return disabled;

    final target = _resolveTarget(context, args);
    if (target == null) return _unknownTarget;

    final localPath = _stringArg(args, 'localPath') ?? '';
    final remotePath = _stringArg(args, 'remotePath') ?? '';
    if (!_localAllowed(context, localPath) ||
        !sessionSshMcpRemotePathAllowed(remotePath, target.folderPaths)) {
      return _pathError;
    }
    if (!await sessionSshMcpLocalSymlinkAllowed(
      fs: context.localFs,
      path: localPath,
      roots: context.localAllowedRoots,
      usesPosixPaths: context.localUsesPosixPaths,
    )) {
      return _pathError;
    }

    try {
      final bytes = await context.localFs.readBytes(localPath);
      if (bytes == null) return _pathError;
      await _executor.upload(
        profile: target.profile,
        bytes: bytes,
        remotePath: remotePath,
      );
      return const SessionSshMcpToolResult.ok('');
    } catch (error) {
      return SessionSshMcpToolResult.error(
        sessionSshMcpErrorSftp,
        _publicError(error),
      );
    }
  }

  Future<SessionSshMcpToolResult> download(
    SessionSshMcpContext context,
    Map<String, Object?> args,
  ) async {
    final disabled = _disabledResult(context);
    if (disabled != null) return disabled;

    final target = _resolveTarget(context, args);
    if (target == null) return _unknownTarget;

    final localPath = _stringArg(args, 'localPath') ?? '';
    final remotePath = _stringArg(args, 'remotePath') ?? '';
    if (!_localAllowed(context, localPath) ||
        !sessionSshMcpRemotePathAllowed(remotePath, target.folderPaths)) {
      return _pathError;
    }

    try {
      final bytes = await _executor.download(
        profile: target.profile,
        remotePath: remotePath,
      );
      await context.localFs.ensureDir(
        context.localFs.pathContext.dirname(localPath),
      );
      await context.localFs.writeBytes(localPath, bytes);
      return const SessionSshMcpToolResult.ok('');
    } catch (error) {
      return SessionSshMcpToolResult.error(
        sessionSshMcpErrorSftp,
        _publicError(error),
      );
    }
  }

  SessionSshMcpToolResult? _disabledResult(SessionSshMcpContext context) {
    if (context.enabled) return null;
    return const SessionSshMcpToolResult.error(
      sessionSshMcpErrorDisabled,
      'SSH MCP is disabled',
    );
  }

  SessionSshMcpTarget? _resolveTarget(
    SessionSshMcpContext context,
    Map<String, Object?> args,
  ) {
    return resolveSessionSshMcpConnection(
      context.targets,
      _stringArg(args, 'connectionName'),
    );
  }

  bool _localAllowed(SessionSshMcpContext context, String path) {
    return sessionSshMcpLocalPathAllowed(
      path,
      context.localAllowedRoots,
      usesPosixPaths: context.localUsesPosixPaths,
    );
  }

  Duration _timeoutOf(Map<String, Object?> args) {
    final raw = args['timeout'];
    if (raw is num) {
      return Duration(milliseconds: raw.toInt());
    }
    return SshStorageIo.ioTimeout;
  }

  static String? _stringArg(Map<String, Object?> args, String key) {
    final raw = args[key];
    return raw is String ? raw : null;
  }

  static String _publicError(Object error) => error.runtimeType.toString();

  static const _unknownTarget = SessionSshMcpToolResult.error(
    sessionSshMcpErrorUnknownTarget,
    'Unknown SSH target. Use list-servers profileId.',
  );

  static const _pathError = SessionSshMcpToolResult.error(
    sessionSshMcpErrorPath,
    'Path is not in the workspace',
  );
}
