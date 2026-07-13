import 'dart:async';

import '../../models/run/launch_configuration.dart';
import '../../models/run/run_ui_intent.dart';
import '../terminal/workspace_terminal_run_service.dart';
import 'launch_type_normalize.dart';
import 'launch_variable_expander.dart';
import 'process_run_executor.dart';
import 'run_session_manager.dart';
import 'run_target_resolver.dart';
import 'shell_script_command_builder.dart';
import 'shell_script_configuration.dart';
import 'shell_script_launch_schema.dart';

/// Launches `shellScript` configs via terminal inject or [ProcessRunExecutor].
class RunShellScriptLauncher implements RunProcessLauncher {
  RunShellScriptLauncher({
    required this.workspaceId,
    required TerminalRunDepsResolver terminalRunDeps,
    required ProcessRunExecutor processExecutor,
    RunTargetResolver? resolver,
    ShellScriptCommandBuilder? commandBuilder,
    void Function(RunUiIntent intent)? emitUiIntent,
    void Function({required String entryId, required String sessionId})?
    registerTerminalSession,
  }) : _terminalRunDeps = terminalRunDeps,
       _processExecutor = processExecutor,
       _resolver = resolver ?? const RunTargetResolver(),
       _commandBuilder = commandBuilder ?? const ShellScriptCommandBuilder(),
       _emitUiIntent = emitUiIntent ?? ((_) {}),
       _registerTerminalSession = registerTerminalSession;

  final String workspaceId;
  final TerminalRunDepsResolver _terminalRunDeps;
  final ProcessRunExecutor _processExecutor;
  final RunTargetResolver _resolver;
  final ShellScriptCommandBuilder _commandBuilder;
  final void Function(RunUiIntent intent) _emitUiIntent;
  final void Function({required String entryId, required String sessionId})?
  _registerTerminalSession;

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
    String? preferTerminalEntryId,
  }) async {
    final expanded = LaunchVariableExpander.expandConfiguration(
      owned.configuration,
      workspaceFolder: owned.owner.path,
      env: owned.configuration.env,
    );

    if (!isBuiltInShellType(expanded.type)) {
      throw StateError(
        'RunShellScriptLauncher only supports shellScript (got ${expanded.type})',
      );
    }

    final errors = ShellScriptLaunchSchema.validate(expanded);
    if (errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }

    final shell = ShellScriptConfiguration.fromLaunchConfiguration(expanded);
    if (shell.executeInTerminal) {
      return _launchInTerminal(
        sessionId: sessionId,
        owned: owned,
        shell: shell,
        preferTerminalEntryId: preferTerminalEntryId,
      );
    }
    return _launchAsProcess(
      sessionId: sessionId,
      owned: owned,
      shell: shell,
      onOutput: onOutput,
    );
  }

  Future<RunLaunchHandle> _launchInTerminal({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required ShellScriptConfiguration shell,
    String? preferTerminalEntryId,
  }) async {
    final deps = _terminalRunDeps.require();
    final group = deps.registry.groupFor(workspaceId);
    final cwd = (shell.cwd?.trim().isNotEmpty ?? false)
        ? shell.cwd!.trim()
        : owned.owner.path;
    final line = _commandBuilder.buildInjectLine(shell);

    final entry = await deps.runService.openForRun(
      workspaceId: workspaceId,
      selectionKey: owned.selectionKey,
      runSessionId: sessionId,
      allowMultipleInstances: shell.allowMultipleInstances,
      preferEntryId: preferTerminalEntryId,
      cwd: cwd,
      targetId: owned.owner.targetId,
      title: owned.configuration.name,
      group: group,
      connector: deps.connector,
      connectCoordinator: deps.connectCoordinator(),
      ops: deps.ops,
      theme: deps.theme(),
      sshConnectFailedMessage: deps.sshConnectFailedMessage(),
    );

    await deps.runService.waitForReady(entry);
    deps.runService.registerSessionEntry(
      sessionId: sessionId,
      entryId: entry.id,
    );
    _registerTerminalSession?.call(entryId: entry.id, sessionId: sessionId);
    deps.runService.inject(entry, line);

    _emitUiIntent(
      RunUiIntent(
        surface: RunToolSurface.terminal,
        activateToolWindow: shell.activateToolWindow,
        focusToolWindow: shell.focusToolWindow,
        terminalEntryId: entry.id,
      ),
    );

    final exitCompleter = Completer<int>();
    return RunLaunchHandle(
      exitCode: exitCompleter.future,
      stop: () async {
        deps.runService.interrupt(entry);
      },
    );
  }

  Future<RunLaunchHandle> _launchAsProcess({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required ShellScriptConfiguration shell,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    final invocation = _commandBuilder.buildProcessInvocation(shell);
    final plan = _resolver.resolve(
      owner: owned.owner,
      cwd: invocation.cwd,
      env: invocation.env,
    );
    final result = await _processExecutor.start(
      sessionId: sessionId,
      command: invocation.command,
      args: invocation.args,
      plan: plan,
      env: invocation.env,
      shell: invocation.shell,
      onOutput: onOutput,
    );
    _emitUiIntent(
      RunUiIntent(
        surface: RunToolSurface.run,
        activateToolWindow: shell.activateToolWindow,
        focusToolWindow: shell.focusToolWindow,
      ),
    );
    return RunLaunchHandle(exitCode: result.exitCode, stop: result.stop);
  }
}
