import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/preset_resolver.dart';
import '../../models/team_config.dart';
import '../cli/registry/launch/cli_launch_arg_assembler.dart';
import '../cli/registry/launch/cli_launch_context.dart' as launch_context;
import '../cli/registry/launch/user_extra_args_provider.dart' as launch_args;
import 'shell_launch_spec.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/cli_invocation.dart';
import '../cli/claude/capabilities/provider.dart';
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
      launch_context.CliLaunchContext(
        team: team,
        member: member,
        launchSecurityPolicy: member.launchSecurityPolicy,
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
    launch_context.CliLaunchContext context, {
    CliToolRegistry? cliRegistry,
  }) {
    final registry = cliRegistry ?? _defaultCliRegistry;
    final cli = stagedMemberLaunchCli(context.team, context.member);
    final tool = registry.tryGet(cli);
    if (tool == null) {
      throw StateError('No CliToolDefinition for ${cli.value}');
    }
    return const CliLaunchArgAssembler().assemble(tool, context);
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

  static List<String> splitArgs(String input) => launch_args.splitArgs(input);

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

  static String normalizePathForCli(String path, {required bool useWslPaths}) =>
      launch_context.normalizePathForCli(path, useWslPaths: useWslPaths);

  static String? windowsPathToWsl(String path) =>
      launch_context.windowsPathToWsl(path);

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
    final value = environment?[ClaudeProviderCapability.settingsFileEnvKey]
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
    ClaudeProviderCapability.settingsFileEnvKey,
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
