import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/links/terminal_link_provider.dart';

import '../cli/cli_executable_validator.dart';
import '../cli/preset_resolver.dart';
import '../cli/cli_invocation.dart';
import '../cli/registry/capabilities/terminal_behavior_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../session/launch_command_builder.dart';
import '../session/shell_launch_spec.dart';
import '../ssh/ssh_member_session.dart';
import '../../cubits/agent_attention_cubit.dart';
import 'pending_user_message.dart';
import 'pty_launch_environment.dart';
import 'terminal_input_controller.dart';
import 'terminal_launch_controller.dart';
import 'terminal_screen_probe_controller.dart';
import 'terminal_session_link_providers.dart';
import 'terminal_transport_starter.dart';
import 'terminal_user_input_pipeline.dart';
import '../team/terminal_activity_tracker.dart';
import '../team_bus/bus_user_line_capture.dart';
import '../../models/workspace_shell_launch_plan.dart';
import '../workspace_dnd/runtime_target.dart';
import '../../utils/logging/logger.dart';
import 'terminal_theme_mapper.dart';

export 'terminal_color_scheme_report.dart' show stripColorSchemeReport;
export 'terminal_input_controller.dart';
export 'terminal_screen_probe_controller.dart';
export 'terminal_transport_starter.dart' show TransportStarter;

/// Session state: engine, connection lifecycle, links, and turn tracking.
///
/// PTY **operations** (write, paste, submit) go through [input]; grid **probes**
/// through [probe]. Composes controllers per SRP / ISP.
class TerminalSession {
  TerminalSession({
    required this.executable,
    this.validateLaunch = true,
    this.usesRemoteTransport = false,
    this.parseExecutable = true,
    this.startupDeadline = const Duration(seconds: 15),
    this.confirmFallback = const Duration(milliseconds: 150),
    TransportStarter? transportStarter,
    int scrollbackLines = 10000,
    TerminalTheme? terminalTheme,
    RuntimeTarget? runtimeTarget,
    TerminalLaunchController? launchController,
    TerminalUserInputPipeline? inputPipeline,
    TerminalInputController? inputController,
    TerminalScreenProbeController? probeController,
    TerminalSessionLinkProviders? linkProviders,
  }) : _scrollbackLines = scrollbackLines,
       _runtimeTarget = runtimeTarget,
       engine = TerminalEngine(
         config: terminalTheme == null
             ? TerminalConfig.defaults().copyWith(
                 scrolling: TerminalConfig.defaults().scrolling.copyWith(
                   history: scrollbackLines,
                 ),
               )
             : terminalConfigFromTheme(
                 terminalTheme,
                 scrollbackLines: scrollbackLines,
               ),
       ),
       activityTracker = launchController?.activityTracker ??
           TerminalActivityTracker(),
       _inputPipeline = inputPipeline ?? TerminalUserInputPipeline(),
       _linkProvidersHolder = linkProviders {
    _terminalTheme = terminalTheme;
    _launch =
        launchController ??
        TerminalLaunchController(
          engine: engine,
          activityTracker: activityTracker,
          defaultExecutable: executable,
          startupDeadline: startupDeadline,
          confirmFallback: confirmFallback,
          validateLaunch: validateLaunch,
          transportStarter: transportStarter,
          scrollbackLines: scrollbackLines,
          terminalTheme: () => _terminalTheme,
        );
    probe = probeController ?? TerminalScreenProbeController(engine: engine);
    input =
        inputController ??
        TerminalInputController(
          launch: _launch,
          onTurnStart: markUserTurnStarted,
          defaultFullscreenSettleDelay: _defaultFullscreenSettleDelay,
        );
    _wireLaunchCallbacks();
    _wireEngineOutput();
  }

  final int _scrollbackLines;
  TerminalTheme? _terminalTheme;

  final String executable;
  final bool validateLaunch;
  final bool usesRemoteTransport;
  final bool parseExecutable;
  final Duration startupDeadline;
  final Duration confirmFallback;

  final TerminalEngine engine;
  final TerminalActivityTracker activityTracker;

  /// PTY writes and full-screen input injection.
  late final TerminalInputController input;

  /// Mirror-grid reads for automation ACK.
  late final TerminalScreenProbeController probe;

  late final TerminalLaunchController _launch;
  final TerminalUserInputPipeline _inputPipeline;
  final TerminalSessionLinkProviders? _linkProvidersHolder;
  TerminalSessionLinkProviders? _linkProviders;

  bool _userTurnActive = false;
  bool get userTurnActive => _userTurnActive;
  void markUserTurnStarted() {
    _userTurnActive = true;
    activityTracker.latchTurnQuietBaseline();
  }

  void markUserTurnIdle() => _userTurnActive = false;

  SshMemberSession? sshMemberSession;

  Map<String, String>? _extraEnvironment;
  Map<String, String>? _ptyEnvironment;
  StreamSubscription<Uint8List>? _engineOutputSubscription;

  String _launchCwd = '';
  RuntimeTarget? _runtimeTarget;

  RuntimeTarget get runtimeTarget => _runtimeTarget ?? _localRuntimeTarget('');

  TerminalPathDropBehavior _pathDropBehavior =
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false);
  TerminalPathDropBehavior get pathDropBehavior => _pathDropBehavior;

  static RuntimeTarget _localRuntimeTarget(String workingDirectory) =>
      Platform.isWindows
      ? RuntimeTarget.localWindows(workingDirectory: workingDirectory)
      : RuntimeTarget.localPosix(workingDirectory: workingDirectory);

  Duration _defaultFullscreenSettleDelay() =>
      (_runtimeTarget?.namespace.isSsh ?? false)
      ? const Duration(milliseconds: 500)
      : TerminalInputController.fullScreenSubmitDelay;

  List<TerminalLinkProvider> get linkProviders =>
      (_linkProviders ??= _linkProvidersHolder ??
              TerminalSessionLinkProviders(engine: engine))
          .build(_launchCwd);

  Stream<PendingUserMessage> get parkedUserSubmissions =>
      _inputPipeline.parkedUserSubmissions;

  bool isUnreadParkedMessage(String id) =>
      _inputPipeline.isUnreadParkedMessage(id);

  bool get isDisposed => _launch.isDisposed;
  int get viewWidth => _launch.pendingViewportCols;
  int get viewHeight => _launch.pendingViewportRows;
  bool get isRunning => _launch.isRunning;
  bool get isConnecting => _launch.isConnecting;
  bool get isConnected => _launch.isConnected;
  bool get transportReadyForIo => _launch.transportReadyForIo;

  void _wireLaunchCallbacks() {
    _launch.writeToDisplay = _writeDisplayNotice;
    _launch.onConfirmedRunning = () => _userTurnActive = false;
  }

  void _wireEngineOutput() {
    _engineOutputSubscription?.cancel();
    _engineOutputSubscription = engine.output.listen((data) {
      final forward = _inputPipeline.transformEngineToPty(data);
      if (forward.isNotEmpty) {
        _launch.writeToPty(forward);
      }
    });
  }

  void _writeDisplayNotice(String text) =>
      _launch.feedPtyBytes(Uint8List.fromList(utf8.encode(text)));

  /// Appends synthetic text to the terminal display (not the child PTY).
  void write(String text) => _writeDisplayNotice(text);

  void applyTerminalTheme(TerminalTheme theme) {
    _terminalTheme = theme;
    if (_launch.isRunning || _launch.isConnecting) {
      engine.reconfigure(
        terminalConfigFromTheme(theme, scrollbackLines: _scrollbackLines),
      );
    }
  }

  void onTerminalPtyResize(int columns, int rows) =>
      _launch.onTerminalPtyResize(columns, rows);

  @visibleForTesting
  void onViewportResize(int columns, int rows) =>
      _launch.onViewportResize(columns, rows);

  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    ShellLaunchSpec? shellLaunch,
    Map<String, String>? extraEnvironment,
    VoidCallback? onProcessStarted,
    void Function(String message)? onProcessFailed,
    VoidCallback? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    BusUserInputRouting? busUserInputRouting,
    String? executableOverride,
  }) {
    if (isDisposed) return;
    _prepareConnect(
      workingDirectory: workingDirectory,
      onProcessStarted: onProcessStarted,
      onProcessFailed: onProcessFailed,
      onProcessExited: onProcessExited,
    );

    final effectiveExecutable =
        (executableOverride != null && executableOverride.trim().isNotEmpty)
        ? executableOverride.trim()
        : executable;
    final invocation = parseExecutable
        ? CliInvocation.fromExecutable(effectiveExecutable)
        : CliInvocation(executable: effectiveExecutable);

    if (!(_runtimeTarget?.namespace.isSsh ?? false)) {
      _runtimeTarget = invocation.usesWsl
          ? RuntimeTarget.wsl(workingDirectory: workingDirectory)
          : _localRuntimeTarget(workingDirectory);
    }
    final ptyWorkingDirectory = LaunchCommandBuilder.workingDirectoryForProcess(
      workingDirectory,
      useWslPaths: invocation.usesWsl,
    );
    final normalizedEnvironment =
        LaunchCommandBuilder.normalizeEnvironmentForCli(
          extraEnvironment,
          useWslPaths: invocation.usesWsl,
        );
    _extraEnvironment = LaunchCommandBuilder.launchEnvironmentForProcess(
      normalizedEnvironment,
    );
    final sshRemote = _runtimeTarget?.namespace.isSsh ?? false;
    _ptyEnvironment = PtyLaunchEnvironment.buildPtyEnvironment(
      _extraEnvironment,
      themeBackground: _terminalTheme?.background,
      inheritHostEnvironment: !sshRemote,
    );

    final args = shellLaunch != null
        ? LaunchCommandBuilder.buildShellArguments(
            shellLaunch,
            fixedSessionId: fixedSessionId,
            resumeSessionId: resumeSessionId,
            environment: normalizedEnvironment,
            useWslPaths: invocation.usesWsl,
          )
        : LaunchCommandBuilder.buildSessionPrefixArgs(
            workingDirectory: workingDirectory.isNotEmpty
                ? workingDirectory
                : null,
            additionalDirectories: additionalDirectories,
            fixedSessionId: fixedSessionId,
            resumeSessionId: resumeSessionId,
            useWslPaths: invocation.usesWsl,
          );
    final launchArgs = invocation.withArgs(
      args,
      environment: _extraEnvironment,
    );

    if (!_validateBeforeSpawn(invocation.executable, ptyWorkingDirectory)) {
      return;
    }

    appLogger.d(
      '--------------------------------\n'
      'Starting transport:\n'
      '--------------------------------\n'
      'Executable: ${invocation.executable},\n'
      'Arguments: ${launchArgs.join(' ')},\n'
      'WorkingDirectory: $ptyWorkingDirectory,\n'
      'Environment: ${normalizedEnvironment?.entries.map((e) => '${e.key}=${e.value}').join(', ')}\n'
      '--------------------------------\n',
    );

    final terminalBehavior = shellLaunch != null
        ? CliToolRegistry.builtIn().capability<TerminalBehaviorCapability>(
            stagedMemberLaunchCli(
              shellLaunch.launchContext.team,
              shellLaunch.launchContext.member,
            ),
          )
        : null;
    final forwardsColorScheme =
        terminalBehavior?.forwardsColorSchemeReport ?? true;
    if (terminalBehavior != null) {
      _pathDropBehavior = terminalBehavior.pathDropBehavior;
    }

    _inputPipeline.install(
      onFirstUserLineSubmitted: onFirstUserLineSubmitted,
      onEveryUserLineSubmitted: onEveryUserLineSubmitted,
      onTurnStart: markUserTurnStarted,
      busUserInputRouting: busUserInputRouting,
      forwardsColorScheme: forwardsColorScheme,
    );

    _launch.onProcessStarted = onProcessStarted;
    _launch.onProcessFailed = onProcessFailed;
    _launch.onProcessExited = onProcessExited;
    _launch.beginStartup(invocation.executable);
    _launch.spawnTransport(
      executable: invocation.executable,
      args: launchArgs,
      cwd: ptyWorkingDirectory,
      environment: _ptyEnvironment,
      cols: viewWidth,
      rows: viewHeight,
    );
  }

  void _prepareConnect({
    required String workingDirectory,
    VoidCallback? onProcessStarted,
    void Function(String message)? onProcessFailed,
    VoidCallback? onProcessExited,
  }) {
    if (_launch.isRunning || _launch.isConnecting) {
      disconnect();
    }
    _launchCwd = workingDirectory;
    _invalidateLinkProviders();
    _launch.onProcessStarted = onProcessStarted;
    _launch.onProcessFailed = onProcessFailed;
    _launch.onProcessExited = onProcessExited;
  }

  bool _validateBeforeSpawn(String executable, String workingDirectory) {
    if (!validateLaunch) return true;
    final validationError = CliExecutableValidator.validateLaunchSyncFast(
      executable: executable,
      workingDirectory: workingDirectory,
    );
    if (validationError != null) {
      _launch.failLaunch(validationError);
      return false;
    }
    return true;
  }

  void connectWorkspaceShell({
    required WorkspaceShellLaunchPlan plan,
    VoidCallback? onProcessStarted,
    void Function(String message)? onProcessFailed,
    VoidCallback? onProcessExited,
  }) {
    if (isDisposed) return;
    _prepareConnect(
      workingDirectory: plan.workingDirectory,
      onProcessStarted: onProcessStarted,
      onProcessFailed: onProcessFailed,
      onProcessExited: onProcessExited,
    );
    _runtimeTarget = plan.usesRemoteTransport
        ? const RuntimeTarget.ssh()
        : (plan.useWslPaths
              ? RuntimeTarget.wsl()
              : _localRuntimeTarget(plan.workingDirectory));
    _extraEnvironment = null;
    _ptyEnvironment = PtyLaunchEnvironment.buildPtyEnvironment(
      null,
      themeBackground: _terminalTheme?.background,
      inheritHostEnvironment: plan.inheritHostEnvironment,
    );

    if (!_validateBeforeSpawn(plan.executable, plan.workingDirectory)) {
      return;
    }
    if (!plan.usesRemoteTransport) {
      final validationError = CliExecutableValidator.validateLaunch(
        executable: plan.executable,
        workingDirectory: plan.workingDirectory,
      );
      if (validationError != null) {
        _launch.failLaunch(validationError);
        return;
      }
    }

    _inputPipeline.installWorkspaceShell();
    _launch.beginStartup(plan.executable);
    _launch.spawnTransport(
      executable: plan.executable,
      args: plan.arguments,
      cwd: plan.workingDirectory,
      environment: _ptyEnvironment,
      cols: viewWidth,
      rows: viewHeight,
    );
  }

  void disconnect() {
    _launch.disconnect();
    _ptyEnvironment = null;
    _inputPipeline.clear();
    _userTurnActive = false;
  }

  /// Cursor seats only: observe live OSC titles for permission attention.
  void bindCursorTitleAttention({
    required String sessionId,
    required String memberId,
    required AgentAttentionCubit attention,
    required bool Function() skipPermissions,
  }) {
    _launch.bindCursorTitleAttention(
      sessionId: sessionId,
      memberId: memberId,
      attention: attention,
      skipPermissions: skipPermissions,
    );
  }

  void dispose() {
    if (isDisposed) return;
    _launch.dispose();
    _invalidateLinkProviders();
    _engineOutputSubscription?.cancel();
    _engineOutputSubscription = null;
    engine.dispose();
    unawaited(_inputPipeline.close());
  }

  void _invalidateLinkProviders() {
    _linkProviders?.dispose();
    _linkProvidersHolder?.invalidate();
    _linkProviders = null;
  }
}
