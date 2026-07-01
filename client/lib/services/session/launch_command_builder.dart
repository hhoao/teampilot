import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/preset_resolver.dart';
import '../../models/team_config.dart';
import '../cli/cli_tool_adapter.dart';
import 'shell_launch_spec.dart';
import '../cli/registry/capabilities/launch_args_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/cli_invocation.dart';
import '../cli/registry/config_profile/claude_config_profile_capability.dart';
import 'member_role_provision.dart';

typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
      Map<String, String>? environment,
      bool includeParentEnvironment,
    });

class LaunchCommandBuilder {
  const LaunchCommandBuilder._();

  /// CLI flags for `--resume` / `--session-id`, `--dir`, and repeated `--add-dir`.
  /// When [resumeSessionId] is non-empty, `--resume` wins over [fixedSessionId].
  static List<String> buildSessionPrefixArgs({
    String? workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    bool useWslPaths = false,
  }) {
    final args = <String>[];
    final resume = resumeSessionId?.trim() ?? '';
    final fixed = fixedSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['--resume', resume]);
    } else if (fixed.isNotEmpty) {
      args.addAll(['--session-id', fixed]);
    }
    final wd = workingDirectory ?? '';
    if (wd.isNotEmpty) {
      args.addAll(['--dir', normalizePathForCli(wd, useWslPaths: useWslPaths)]);
    }
    for (final path in additionalDirectories) {
      final t = path.trim();
      if (t.isNotEmpty) {
        args.addAll([
          '--add-dir',
          normalizePathForCli(t, useWslPaths: useWslPaths),
        ]);
      }
    }
    return args;
  }

  static final _defaultCliRegistry = () {
    final r = CliToolRegistry.builtIn();
    return r;
  }();

  static List<String> buildArguments(
    TeamProfile team,
    TeamMemberConfig member, {
    String? sessionTeam,
    String? workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    String? settingsPath,
    String? appendSystemPromptFile,
    bool useWslPaths = false,
    CliToolRegistry? cliRegistry,
  }) {
    return buildArgumentsFromContext(
      CliLaunchContext(
        team: team,
        member: member,
        sessionTeam: sessionTeam,
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
        fixedSessionId: fixedSessionId,
        resumeSessionId: resumeSessionId,
        settingsPath: settingsPath,
        appendSystemPromptFile: appendSystemPromptFile,
        useWslPaths: useWslPaths,
      ),
      cliRegistry: cliRegistry,
    );
  }

  static List<String> buildArgumentsFromContext(
    CliLaunchContext context, {
    CliToolRegistry? cliRegistry,
  }) {
    final registry = cliRegistry ?? _defaultCliRegistry;
    final cli = stagedMemberLaunchCli(context.team, context.member);
    final launch = registry.capability<LaunchArgsCapability>(cli);
    if (launch == null) {
      throw StateError('No LaunchArgsCapability for ${cli.value}');
    }
    return launch.buildArguments(context);
  }

  /// CLI argv for [TerminalSession.connect] after env normalization.
  static List<String> buildShellArguments(
    ShellLaunchSpec spec, {
    String? fixedSessionId,
    String? resumeSessionId,
    Map<String, String>? environment,
    bool useWslPaths = false,
    CliToolRegistry? cliRegistry,
  }) {
    return buildArgumentsFromContext(
      spec.launchContext.copyWith(
        sessionTeam: spec.sessionTeam,
        fixedSessionId: fixedSessionId,
        resumeSessionId: resumeSessionId,
        settingsPath: settingsPathFromEnvironment(environment),
        appendSystemPromptFile: appendSystemPromptFileFromEnvironment(
          environment,
        ),
        useWslPaths: useWslPaths,
      ),
      cliRegistry: cliRegistry,
    );
  }

  static String preview(
    TeamProfile team,
    TeamMemberConfig member, {
    String? sessionTeam,
    required String executable,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
  }) {
    final invocation = CliInvocation.fromExecutable(executable);
    return [
      invocation.executable,
      ...invocation.prefixArgs,
      ...buildArguments(
        team,
        member,
        sessionTeam: sessionTeam,
        workingDirectory: '',
        additionalDirectories: additionalDirectories,
        fixedSessionId: fixedSessionId,
        resumeSessionId: resumeSessionId,
        useWslPaths: invocation.usesWsl,
      ),
    ].map(_quoteForPreview).join(' ');
  }

  static List<String> splitArgs(String input) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var escaping = false;

    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (escaping) {
        buffer.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\') {
        escaping = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          args.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }

    if (escaping) {
      buffer.write(r'\');
    }
    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }
    return args;
  }

  static Future<void> launch(
    TeamProfile team, {
    required TeamMemberConfig member,
    required String executable,
    String? sessionTeam,
    String? workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    Map<String, String>? extraEnvironment,
    ProcessStarter starter = Process.start,
    bool launchInExternalTerminal = true,
  }) async {
    final wd = workingDirectory ?? '';
    final invocation = CliInvocation.fromExecutable(executable);
    final processWorkingDirectory = workingDirectoryForProcess(
      wd,
      useWslPaths: invocation.usesWsl,
    );
    final normalizedEnvironment = invocation.usesWsl
        ? normalizeEnvironmentForCli(extraEnvironment, useWslPaths: true)
        : extraEnvironment;
    final settingsPath = settingsPathFromEnvironment(normalizedEnvironment);
    final appendSystemPromptFile = appendSystemPromptFileFromEnvironment(
      normalizedEnvironment,
    );
    final env = launchEnvironmentForProcess(normalizedEnvironment);
    final args = buildArguments(
      team,
      member,
      sessionTeam: sessionTeam,
      workingDirectory: wd,
      additionalDirectories: additionalDirectories,
      fixedSessionId: fixedSessionId,
      resumeSessionId: resumeSessionId,
      settingsPath: settingsPath,
      appendSystemPromptFile: appendSystemPromptFile,
      useWslPaths: invocation.usesWsl,
    );
    final launchArgs = invocation.withArgs(args, environment: env);

    if (launchInExternalTerminal && Platform.isLinux) {
      if (await _tryStartTerminal(
        starter,
        'x-terminal-emulator',
        ['-e', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
      if (await _tryStartTerminal(
        starter,
        'gnome-terminal',
        ['--', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
      if (await _tryStartTerminal(
        starter,
        'konsole',
        ['-e', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
      if (await _tryStartTerminal(
        starter,
        'xterm',
        ['-e', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
    } else if (launchInExternalTerminal && Platform.isMacOS) {
      // `open -a Terminal` does not propagate parent env to the spawned shell.
      // Inline `export` so flashskyai sees the values we want.
      final exports = env == null || env.isEmpty
          ? ''
          : '${env.entries.map((e) => 'export ${e.key}=${_shellQuote(e.value)}').join('; ')}; ';
      final script =
          '${exports}cd ${_shellQuote(wd)} && '
          '${_shellQuote(invocation.executable)} ${launchArgs.map(_shellQuote).join(' ')}';
      if (await _tryStartTerminal(
        starter,
        'open',
        ['-a', 'Terminal', script],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
    } else if (launchInExternalTerminal && Platform.isWindows) {
      // `cmd /c start ... cmd /k` doesn't reliably forward parent env. Prefix
      // explicit `set` commands so flashskyai sees them in the new console.
      final sets = env == null || env.isEmpty
          ? ''
          : '${env.entries.map((e) => 'set ${e.key}=${e.value}').join(' && ')} && ';
      final command =
          '$sets${[invocation.executable, ...launchArgs].map(_windowsQuote).join(' ')}';
      if (await _tryStartTerminal(
        starter,
        'cmd',
        ['/c', 'start', 'FlashskyAI', 'cmd', '/k', command],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
    }

    await starter(
      invocation.executable,
      launchArgs,
      workingDirectory: processWorkingDirectory,
      runInShell: true,
      environment: env,
      includeParentEnvironment: true,
    );
  }

  static Future<bool> _tryStartTerminal(
    ProcessStarter starter,
    String terminal,
    List<String> args,
    String workingDirectory,
    Map<String, String>? environment,
  ) async {
    try {
      await starter(
        terminal,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
        environment: environment,
        includeParentEnvironment: true,
      );
      return true;
    } on IOException {
      return false;
    }
  }

  static String _quoteForPreview(String value) {
    if (value.isEmpty) {
      return "''";
    }
    if (!value.contains(RegExp(r'\s'))) {
      return value;
    }
    return _shellQuote(value);
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static String _windowsQuote(String value) {
    if (!value.contains(RegExp(r'\s'))) {
      return value;
    }
    return '"${value.replaceAll('"', r'\"')}"';
  }

  static String normalizePathForCli(String path, {required bool useWslPaths}) {
    if (!useWslPaths) return path;
    return windowsPathToWsl(path) ?? path;
  }

  static String? windowsPathToWsl(String path) {
    final trimmed = path.trim();
    final uncMatch = RegExp(
      r'^\\+(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed.replaceAll('/', r'\'));
    if (uncMatch != null) {
      return '/${uncMatch.group(1)!.replaceAll(r'\', '/')}';
    }

    final match = RegExp(r'^([a-zA-Z]):[\\/]*(.*)$').firstMatch(trimmed);
    if (match == null) return null;
    final drive = match.group(1)!.toLowerCase();
    final rest = match.group(2)!.replaceAll('\\', '/');
    return rest.isEmpty ? '/mnt/$drive' : '/mnt/$drive/$rest';
  }

  /// Inverse of [windowsPathToWsl] for `/mnt/<drive>/...` paths.
  static String? wslPathToWindows(String path) {
    final trimmed = path.trim();
    if (!trimmed.startsWith('/')) return null;

    final normalized = p.Context(style: p.Style.posix).normalize(trimmed);
    final match = RegExp(r'^/mnt/([a-zA-Z])(?:/(.*))?$').firstMatch(normalized);
    if (match == null) return null;

    final drive = match.group(1)!.toUpperCase();
    final rest = match.group(2);
    if (rest == null || rest.isEmpty) {
      return '$drive:\\';
    }
    return p.normalize('$drive:\\${rest.replaceAll('/', r'\')}');
  }

  static String workingDirectoryForProcess(
    String workingDirectory, {
    required bool useWslPaths,
  }) {
    if (!useWslPaths) return workingDirectory;
    if (!Platform.isWindows) return workingDirectory;
    // Windows PTY wraps `wsl.exe`; CreateProcess cwd must be a native path.
    // Workspace dirs are passed separately via CLI args in WSL form.
    final userProfile = Platform.environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }
    final systemRoot = Platform.environment['SystemRoot']?.trim();
    if (systemRoot != null && systemRoot.isNotEmpty) {
      return systemRoot;
    }
    return Directory.current.path;
  }

  static Map<String, String>? normalizeEnvironmentForCli(
    Map<String, String>? environment, {
    required bool useWslPaths,
  }) {
    if (environment == null || !useWslPaths) return environment;
    return {
      for (final entry in environment.entries)
        entry.key: normalizePathForCli(entry.value, useWslPaths: true),
    };
  }

  static String? settingsPathFromEnvironment(Map<String, String>? environment) {
    final value = environment?[ClaudeConfigProfileCapability.settingsFileEnvKey]
        ?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? appendSystemPromptFileFromEnvironment(
    Map<String, String>? environment,
  ) {
    final value = environment?[MemberRoleProvision.appendSystemPromptFileEnvKey]
        ?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static const _launchOnlyEnvKeys = {
    ClaudeConfigProfileCapability.settingsFileEnvKey,
    MemberRoleProvision.appendSystemPromptFileEnvKey,
  };

  static Map<String, String>? launchEnvironmentForProcess(
    Map<String, String>? environment,
  ) {
    if (environment == null) return null;
    if (!_launchOnlyEnvKeys.any(environment.containsKey)) {
      return environment;
    }
    return {
      for (final entry in environment.entries)
        if (!_launchOnlyEnvKeys.contains(entry.key)) entry.key: entry.value,
    };
  }
}
