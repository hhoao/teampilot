import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_pty/flutter_pty.dart';
import '../cli/cli_executable_validator.dart';
import '../cli/preset_resolver.dart';
import '../cli/cli_invocation.dart';
import '../cli/cli_tool_locator.dart';
import '../cli/registry/capabilities/terminal_behavior_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../session/launch_command_builder.dart';
import '../session/shell_launch_spec.dart';
import '../ssh/ssh_member_session.dart';
import 'local_pty_transport.dart';
import 'pty_launch_environment.dart';
import 'terminal_color_scheme_report.dart';
import 'terminal_transport.dart';

export 'terminal_color_scheme_report.dart' show stripColorSchemeReport;
import '../team/terminal_activity_tracker.dart';
import '../team_bus/bus_user_line_capture.dart';
import 'pending_user_message.dart';
import '../../utils/first_user_line_capture.dart';
import '../../utils/every_user_line_capture.dart';
import '../../utils/logger.dart';
import 'terminal_theme_mapper.dart';
import '../../models/workspace_shell_launch_plan.dart';
import '../storage/app_storage.dart';
import '../workspace_dnd/runtime_target.dart';
import '../workspace_dnd/terminal_text_sink.dart';
import 'file_path_link_provider.dart';
import 'terminal_uri_opener.dart';

typedef TransportStarter =
    Future<TerminalTransport> Function(
      String executable, {
      required List<String> arguments,
      required String workingDirectory,
      required int columns,
      required int rows,
      Map<String, String>? environment,
    });

/// PTY attach → confirm → running. See [_feedPtyBytes] and [_confirmProcessStarted].
enum _LaunchPhase { idle, spawning, confirming, running, failed }

class TerminalSession implements TerminalTextSink {
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
    @Deprecated('Use transportStarter instead') dynamic ptyStarter,
  }) : _transportStarter = transportStarter ?? _defaultTransportStarter,
       _runtimeTarget = runtimeTarget,
       _scrollbackLines = scrollbackLines,
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
       ) {
    _terminalTheme = terminalTheme;
  }

  final int _scrollbackLines;
  TerminalTheme? _terminalTheme;

  final String executable;
  final bool validateLaunch;
  final bool usesRemoteTransport;
  final bool parseExecutable;
  final Duration startupDeadline;
  final Duration confirmFallback;
  final TransportStarter _transportStarter;

  /// Alacritty-backed terminal engine (replaces xterm [Terminal]).
  final TerminalEngine engine;

  final TerminalActivityTracker activityTracker = TerminalActivityTracker();

  /// Single-CLI working-turn state — mirrors mixed-mode bus turn truth without a
  /// bus. A turn *begins* on a **send** (the user submitting a line, or a
  /// programmatic prompt injection) and *ends* when PTY output goes quiet,
  /// detected as the [activityTracker] falling edge by [TabTeamBusCoordinator].
  /// Drives the sidebar/tab working spinner in simple & native single-CLI mode.
  /// Screen output never *enters* working — it only clears it (team-mode parity).
  bool _userTurnActive = false;
  bool get userTurnActive => _userTurnActive;
  void markUserTurnStarted() => _userTurnActive = true;
  void markUserTurnIdle() => _userTurnActive = false;
  TerminalTransport? _transport;
  var _launchPhase = _LaunchPhase.idle;

  /// Session-plane SSH connection for remote members. Set by [SessionLaunchService]
  /// before [connect] when the launch target is ssh.
  SshMemberSession? sshMemberSession;
  var _startFailed = false;
  String? _startupExecutable;
  Map<String, String>? _extraEnvironment;
  Map<String, String>? _ptyEnvironment;
  VoidCallback? _onProcessStarted;
  void Function(String message)? _onProcessFailed;
  VoidCallback? _onProcessExited;
  StreamSubscription<Uint8List>? _outputSubscription;
  StreamSubscription<Uint8List>? _engineOutputSubscription;
  FirstUserLineCapture? _firstUserLineCapture;
  EveryUserLineCapture? _everyUserLineCapture;

  /// Always-on capture (independent of [onEveryUserLineSubmitted]) marking a
  /// working turn whenever the user submits a line — the "send → working" edge.
  EveryUserLineCapture? _turnStartCapture;
  BusUserLineCapture? _busUserLineCapture;
  final StreamController<PendingUserMessage> _parkedSubmissions =
      StreamController<PendingUserMessage>.broadcast();
  BusUserInputRouting? _busRouting;

  /// The working directory most recently passed to [connect]. Used as
  /// [FilePathLinkProvider.launchCwd] so file-path links resolve correctly.
  /// Empty string until the first [connect] call.
  String _launchCwd = '';

  /// The execution namespace this terminal's process lives in. SSH sessions are
  /// tagged at construction (the factory knows the remote); local sessions are
  /// resolved at [connect] from the platform + whether the launch wraps WSL.
  /// Drives drag-and-drop path projection (see `workspace_dnd/`).
  RuntimeTarget? _runtimeTarget;

  /// The terminal's runtime namespace, defaulting to the local host when a
  /// session has not been connected yet.
  RuntimeTarget get runtimeTarget => _runtimeTarget ?? _localRuntimeTarget('');

  /// How a dropped file path is quoted and injected for this session's CLI,
  /// resolved from the terminal-behavior capability at [connect]. Falls back to
  /// the line-edited default before the first connect (or for shell-only specs).
  TerminalPathDropBehavior _pathDropBehavior =
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false);
  TerminalPathDropBehavior get pathDropBehavior => _pathDropBehavior;

  static RuntimeTarget _localRuntimeTarget(String workingDirectory) =>
      Platform.isWindows
      ? RuntimeTarget.localWindows(workingDirectory: workingDirectory)
      : RuntimeTarget.localPosix(workingDirectory: workingDirectory);

  List<TerminalLinkProvider>? _linkProviders;
  ValueNotifier<String?>? _osc7Cwd;

  /// Link providers for this session's TerminalView: clickable URLs + file
  /// paths (validated against the filesystem, resolved against the live cwd).
  List<TerminalLinkProvider> get linkProviders =>
      _linkProviders ??= _buildLinkProviders();

  List<TerminalLinkProvider> _buildLinkProviders() {
    // Track the shell's cwd from OSC 7 (`file://host/path`) reports so relative
    // path links re-resolve after `cd`. Falls back to the launch cwd whenever
    // the report is absent or not a parseable local path.
    final cwd = ValueNotifier<String?>(parseOsc7Cwd(engine.workingDir.value));
    engine.workingDir.addListener(_syncOsc7Cwd);
    _osc7Cwd = cwd;
    return [
      UrlLinkProvider(),
      FilePathLinkProvider(fs: AppStorage.fs, launchCwd: _launchCwd, cwd: cwd),
    ];
  }

  /// Drops cached link providers so the next [linkProviders] read rebuilds with
  /// the current [_launchCwd]. [TerminalView] may materialize during
  /// `sessionConnecting` before [connect] assigns the project directory.
  void _disposeLinkProviders() {
    final providers = _linkProviders;
    if (providers == null) return;
    engine.workingDir.removeListener(_syncOsc7Cwd);
    for (final p in providers) {
      p.dispose();
    }
    _osc7Cwd?.dispose();
    _osc7Cwd = null;
    _linkProviders = null;
  }

  void _syncOsc7Cwd() =>
      _osc7Cwd?.value = parseOsc7Cwd(engine.workingDir.value);

  /// Parses an OSC 7 working-directory report (`file://host/path`) into a local
  /// directory path, or `null` when it is empty, remote, or unparseable.
  @visibleForTesting
  static String? parseOsc7Cwd(String raw) {
    if (raw.trim().isEmpty) return null;
    return TerminalUriOpener.resolveLocalFilePath(raw);
  }

  /// Lines submitted to the bus while parked. The overlay subscribes to show a
  /// "sent, awaiting receipt" banner per message.
  Stream<PendingUserMessage> get parkedUserSubmissions =>
      _parkedSubmissions.stream;

  /// Whether a previously-submitted parked message is still unread by its
  /// recipient. Used by the overlay to clear the banner once consumed.
  bool isUnreadParkedMessage(String id) =>
      _busRouting?.isUnread?.call(id) ?? false;

  Timer? _confirmFallbackTimer;
  Timer? _startupDeadlineTimer;
  var _spawnRequested = false;
  var _transportStartGeneration = 0;
  var _disposed = false;

  /// True after [dispose]; blocks [connect] and in-flight [_startTransport].
  bool get isDisposed => _disposed;

  bool _startTransportAborted(int startGeneration) =>
      _disposed ||
      startGeneration != _transportStartGeneration ||
      !_starting;
  int _pendingViewportCols = 80;
  int _pendingViewportRows = 24;

  /// Serializes [submitFullScreenInput] so overlapping bracketed-paste + CR
  /// injections never interleave their carriage returns.
  Future<void> _ptySubmitChain = Future<void>.value();

  /// Settle window between bracketed-paste content and the standalone CR for
  /// full-screen TUI CLIs, matching Claude Code's own ~10ms child-PTY delay.
  static const _fullScreenSubmitDelay = Duration(milliseconds: 10);

  int get viewWidth => _pendingViewportCols;
  int get viewHeight => _pendingViewportRows;

  bool get isRunning =>
      (_launchPhase == _LaunchPhase.running ||
          _launchPhase == _LaunchPhase.confirming ||
          _launchPhase == _LaunchPhase.spawning) &&
      !_startFailed;

  /// Spawning or awaiting first output confirmation.
  bool get isConnecting =>
      !_startFailed &&
      (_launchPhase == _LaunchPhase.spawning ||
          _launchPhase == _LaunchPhase.confirming);

  /// PTY confirmed running (agent may still be idle).
  bool get isConnected => !_startFailed && _launchPhase == _LaunchPhase.running;

  bool get _starting =>
      _launchPhase == _LaunchPhase.spawning ||
      _launchPhase == _LaunchPhase.confirming;

  bool get _running => _transport != null && _launchPhase != _LaunchPhase.idle;

  /// Writes PTY output bytes into the display engine.
  void write(String text) => _writeOutput(text);

  /// Push TeamPilot layout colors into the Rust engine palette (ANSI + default fg/bg).
  ///
  /// [TerminalView.theme] only affects selection/search chrome; cell colors come
  /// from the engine until this is called (xterm parity).
  void applyTerminalTheme(TerminalTheme theme) {
    _terminalTheme = theme;
    if (_running || _starting) {
      _reconfigureEngineColors(theme);
    }
  }

  void _reconfigureEngineColors(TerminalTheme theme) {
    engine.reconfigure(
      terminalConfigFromTheme(theme, scrollbackLines: _scrollbackLines),
    );
  }

  /// Called from [TerminalView.onPtyResize] when the view commits a new grid.
  ///
  /// The view owns [engine.resize]; this only tracks pending geometry and
  /// SIGWINCHs the PTY once the transport is ready.
  void onTerminalPtyResize(int columns, int rows) {
    if (columns < kMinTerminalColumns || rows < kMinTerminalRows) return;
    _pendingViewportCols = columns;
    _pendingViewportRows = rows;
    if (!_transportReadyForIo || _transport == null) {
      _pendingPtyResizeCols = columns;
      _pendingPtyResizeRows = rows;
      return;
    }
    _transport!.resize(rows, columns);
  }

  /// Legacy test shim: resizes the engine and PTY without a mounted [TerminalView].
  @Deprecated('Tests only — production uses TerminalView.onPtyResize')
  void onViewportResize(int columns, int rows) {
    if (columns < kMinTerminalColumns || rows < kMinTerminalRows) return;
    _pendingViewportCols = columns;
    _pendingViewportRows = rows;
    engine.resize(columns: columns, rows: rows);
    _syncPtyGeometryNow(columns, rows);
    _scheduleLayoutPtyGeometrySettle();
  }

  /// A PTY resize that arrived before the transport was ready. Flushed by
  /// [_flushPendingPtyResize] once the transport enters the confirming phase.
  int? _pendingPtyResizeCols;
  int? _pendingPtyResizeRows;

  void _flushPendingPtyResize() {
    final cols = _pendingPtyResizeCols;
    final rows = _pendingPtyResizeRows;
    _pendingPtyResizeCols = null;
    _pendingPtyResizeRows = null;
    if (cols == null || rows == null) return;
    if (!_transportReadyForIo || _transport == null) return;
    _transport!.resize(rows, cols);
  }

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
    if (_disposed) return;
    _prepareConnect(
      workingDirectory: workingDirectory,
      onProcessStarted: onProcessStarted,
      onProcessFailed: onProcessFailed,
      onProcessExited: onProcessExited,
    );
    // P3c: an off-home remote member launches the CLI at the path preflight
    // located on the work machine (else the session's resolved executable).
    final effectiveExecutable =
        (executableOverride != null && executableOverride.trim().isNotEmpty)
        ? executableOverride.trim()
        : executable;
    final invocation = parseExecutable
        ? CliInvocation.fromExecutable(effectiveExecutable)
        : CliInvocation(executable: effectiveExecutable);
    // Resolve the drag-and-drop path namespace for local sessions. SSH sessions
    // are tagged at construction (the factory knows the remote) and kept as-is;
    // a local launch is WSL when it wraps `wsl.exe`, else the host platform.
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
    _ptyEnvironment = buildPtyEnvironment(
      _extraEnvironment,
      themeBackground: _terminalTheme?.background,
      // SSH members run on the work machine — never forward the control-plane
      // host's Platform.environment (proxy / ANTHROPIC_BASE_URL on 127.0.0.1).
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

    _beginStartup(invocation.executable);

    _firstUserLineCapture = onFirstUserLineSubmitted == null
        ? null
        : FirstUserLineCapture(onFirstUserLineSubmitted);
    _everyUserLineCapture = onEveryUserLineSubmitted == null
        ? null
        : EveryUserLineCapture(onEveryUserLineSubmitted);
    _turnStartCapture = EveryUserLineCapture((_) => markUserTurnStarted());
    final incomingRouting = busUserInputRouting;
    _busRouting = incomingRouting;
    _busUserLineCapture = incomingRouting == null
        ? null
        : BusUserLineCapture(
            BusUserInputRouting(
              shouldIntercept: incomingRouting.shouldIntercept,
              isUnread: incomingRouting.isUnread,
              onTurnStart: incomingRouting.onTurnStart,
              onUserLine: (line) {
                final id = incomingRouting.onUserLine(line);
                if (id.isNotEmpty) {
                  _parkedSubmissions.add(
                    PendingUserMessage(id: id, content: line),
                  );
                }
                return id;
              },
            ),
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

    _listenEngineOutput((data) {
      if (_firstUserLineCapture != null ||
          _everyUserLineCapture != null ||
          _turnStartCapture != null) {
        // Decode once and share — the engine may split a multi-byte glyph across
        // chunks, so allow malformed sequences (PTY output path does the same).
        final decoded = utf8.decode(data, allowMalformed: true);
        _firstUserLineCapture?.feed(decoded);
        _everyUserLineCapture?.feed(decoded);
        _turnStartCapture?.feed(decoded);
      }
      var forward = _busUserLineCapture?.filter(data) ?? data;
      if (!forwardsColorScheme) {
        forward = stripColorSchemeReport(forward);
      }
      return forward;
    });

    _spawnTransport(
      executable: invocation.executable,
      args: launchArgs,
      cwd: ptyWorkingDirectory,
      cols: viewWidth,
      rows: viewHeight,
    );
  }

  /// Shared prologue for [connect] and [connectShell]: tear down any in-flight
  /// launch, record the launch cwd, and (re)install the lifecycle callbacks.
  void _prepareConnect({
    required String workingDirectory,
    VoidCallback? onProcessStarted,
    void Function(String message)? onProcessFailed,
    VoidCallback? onProcessExited,
  }) {
    if (_running || _starting) {
      disconnect();
    }
    _launchCwd = workingDirectory;
    _disposeLinkProviders();
    _onProcessStarted = onProcessStarted;
    _onProcessFailed = onProcessFailed;
    _onProcessExited = onProcessExited;
    _startFailed = false;
  }

  /// Runs the fast synchronous launch precheck, failing the session and
  /// returning `false` when the executable/cwd is invalid. Returns `true` (and
  /// is a no-op) when [validateLaunch] is disabled.
  bool _validateBeforeSpawn(String executable, String workingDirectory) {
    if (!validateLaunch) return true;
    final validationError = CliExecutableValidator.validateLaunchSyncFast(
      executable: executable,
      workingDirectory: workingDirectory,
    );
    if (validationError != null) {
      _handleStartFailure(validationError);
      return false;
    }
    return true;
  }

  /// Subscribes to engine→PTY output. [transform] may run capture side effects
  /// and return the bytes to forward (e.g. bus filtering, OSC 997 stripping);
  /// when null the raw bytes are forwarded verbatim (plain interactive shell).
  void _listenEngineOutput(Uint8List Function(Uint8List data)? transform) {
    _engineOutputSubscription?.cancel();
    _engineOutputSubscription = engine.output.listen((Uint8List data) {
      final forward = transform?.call(data) ?? data;
      if (forward.isNotEmpty && _transportReadyForIo && _transport != null) {
        _transport!.write(forward);
      }
    });
  }

  /// Interactive login shell for the workspace terminal panel (no CLI flags).
  void connectWorkspaceShell({
    required WorkspaceShellLaunchPlan plan,
    VoidCallback? onProcessStarted,
    void Function(String message)? onProcessFailed,
    VoidCallback? onProcessExited,
  }) {
    if (_disposed) return;
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
    _ptyEnvironment = buildPtyEnvironment(
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
        _handleStartFailure(validationError);
        return;
      }
    }

    _beginStartup(plan.executable);

    _firstUserLineCapture = null;
    _everyUserLineCapture = null;
    _busUserLineCapture = null;

    _listenEngineOutput(null);

    _spawnTransport(
      executable: plan.executable,
      args: plan.arguments,
      cwd: plan.workingDirectory,
      cols: viewWidth,
      rows: viewHeight,
    );
  }

  /// Direct PTY resize — no timers, no settle, no debounce. Used only by the
  /// deprecated [onViewportResize] test shim.
  void _syncPtyGeometryNow(int cols, int rows) {
    if (cols <= 0 || rows <= 0) return;
    if (_transport == null) return;
    if (!_transportReadyForIo) return;
    _transport!.resize(rows, cols);
  }

  /// 80ms settle after a legacy layout resize; kept for deprecated [onViewportResize].
  void _scheduleLayoutPtyGeometrySettle() {
    Timer(const Duration(milliseconds: 80), () {
      if (_transport == null || !_transportReadyForIo) return;
      _syncPtyGeometryNow(_pendingViewportCols, _pendingViewportRows);
    });
  }

  void _spawnTransport({
    required String executable,
    required List<String> args,
    required String cwd,
    required int cols,
    required int rows,
  }) {
    if (_spawnRequested || _transport != null) return;
    _spawnRequested = true;

    _startTransport(
      executable: executable,
      args: args,
      cwd: cwd,
      cols: cols,
      rows: rows,
    );
  }

  bool get _transportReadyForIo =>
      _transport != null &&
      (_launchPhase == _LaunchPhase.confirming ||
          _launchPhase == _LaunchPhase.running);

  void _beginStartup(String executable) {
    _startupExecutable = executable;
    _launchPhase = _LaunchPhase.spawning;
    _startFailed = false;
    _armStartupDeadline();
  }

  void _enterConfirmingPhase() {
    if (_launchPhase != _LaunchPhase.spawning) return;
    _launchPhase = _LaunchPhase.confirming;
    // Transport is now ready for I/O — flush any resize that arrived while it
    // was still spawning.
    _flushPendingPtyResize();
    _confirmFallbackTimer?.cancel();
    _confirmFallbackTimer = Timer(confirmFallback, _confirmProcessStarted);
  }

  void _armStartupDeadline() {
    _startupDeadlineTimer?.cancel();
    _startupDeadlineTimer = Timer(startupDeadline, _onStartupDeadline);
  }

  void _onStartupDeadline() {
    if (!_starting || _startFailed) return;
    final cliExecutable = _startupExecutable ?? executable;
    final cliName = CliExecutableValidator.cliDisplayName(cliExecutable);
    if (_transport == null) {
      _handleStartFailure('[Failed to start $cliName: spawn timed out]');
      return;
    }
    _handleStartFailure('[Failed to start $cliName: startup timed out]');
  }

  void _cancelStartupTimers() {
    _confirmFallbackTimer?.cancel();
    _confirmFallbackTimer = null;
    _startupDeadlineTimer?.cancel();
    _startupDeadlineTimer = null;
  }

  /// Feeds raw PTY output bytes into the display engine. Hot path: avoids any
  /// String/UTF-8 conversion. See [_writeOutput] for the String entry point used
  /// by synthetic writes (failure/exit notices).
  void _feedPtyBytes(Uint8List data) {
    if (data.isEmpty) return;
    if (isConnected) {
      activityTracker.markActive();
    }
    engine.feed(data);
    // PTY geometry is managed by TerminalView.onPtyResize → onTerminalPtyResize.
  }

  Future<void> _startTransport({
    required String executable,
    required List<String> args,
    required String cwd,
    required int cols,
    required int rows,
  }) async {
    final startGeneration = ++_transportStartGeneration;
    try {
      // Yield to the event loop so the loading animation can paint before the
      // synchronous Rust FFI call (engineNew) blocks the main thread.
      await Future<void>.delayed(Duration.zero);
      if (_startTransportAborted(startGeneration)) return;

      // By now the view may have mounted and reported the real grid via
      // onTerminalPtyResize; fall back to the connect-time guess otherwise.
      final startCols = _pendingViewportCols;
      final startRows = _pendingViewportRows;
      engine.resize(columns: startCols, rows: startRows);
      engine.initializeEmpty(startRows, startCols);
      final theme = _terminalTheme;
      if (theme != null) {
        _reconfigureEngineColors(theme);
      }

      if (validateLaunch) {
        final validationError =
            await CliExecutableValidator.validateLaunchPathLookupAsync(
              executable,
            );
        if (validationError != null) {
          if (!_startTransportAborted(startGeneration)) {
            _spawnRequested = false;
            _handleStartFailure(validationError);
          }
          return;
        }
        if (_startTransportAborted(startGeneration)) return;
      }
      // PTY still spawns at the connect-time guess (cols/rows) by design;
      // [_flushPendingPtyResize] reconciles to [onTerminalPtyResize] geometry
      // once the transport enters the confirming phase.
      final transport = await _transportStarter(
        executable,
        arguments: args,
        workingDirectory: cwd,
        columns: cols,
        rows: rows,
        environment: _ptyEnvironment,
      );
      if (_startTransportAborted(startGeneration)) {
        transport.close();
        return;
      }
      _transport = transport;
      _enterConfirmingPhase();

      _outputSubscription = transport.output.listen((Uint8List data) {
        if (data.isEmpty) return;
        _feedPtyBytes(data);
        final text = utf8.decode(data, allowMalformed: true);
        if (_looksLikeCliStartupFailure(text)) {
          appLogger.e('[terminal] CLI error: ${text.trim()}');
        }
        if (!_starting || _startFailed) return;
        if (_looksLikeCliStartupFailure(text)) {
          _handleStartFailure(_launchFailureMessage(executable));
          return;
        }
        if (_looksLikeExecFailure(text)) {
          _handleStartFailure(_launchFailureMessage(executable));
          return;
        }
        _confirmProcessStarted();
      });

      transport.done.then((code) {
        if (_disposed ||
            startGeneration != _transportStartGeneration ||
            _transport != transport) {
          return;
        }
        if (_starting && !_startFailed) {
          _handleStartFailure(
            code == 0
                ? '[process exited unexpectedly during startup]'
                : '[process exited with code $code during startup]',
          );
          return;
        }
        if (_launchPhase != _LaunchPhase.running) {
          return;
        }
        if (code != 0) {
          final message = '[process exited with code $code]';
          appLogger.w(
            '[terminal] $message '
            '(executable: ${CliExecutableValidator.cliDisplayName(executable)})',
          );
          write('\r\n$message\r\n');
          return;
        }
        if (_transport == transport) {
          transport.close();
          _transport = null;
        }
        _teardownPtyState();
        final callback = _onProcessExited;
        _onProcessExited = null;
        callback?.call();
      });
    } on Object catch (error, stackTrace) {
      if (_startTransportAborted(startGeneration)) {
        return;
      }
      final cliName = CliExecutableValidator.cliDisplayName(executable);
      _handleStartFailure(
        '[Failed to start $cliName: $error]',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _confirmProcessStarted() {
    if (_launchPhase != _LaunchPhase.confirming ||
        _startFailed ||
        _transport == null) {
      return;
    }
    _launchPhase = _LaunchPhase.running;
    activityTracker.reset();
    _userTurnActive = false;
    _cancelStartupTimers();
    final cliExecutable = _startupExecutable ?? executable;
    appLogger.d(
      '[terminal] started ${CliExecutableValidator.cliDisplayName(cliExecutable)}',
    );
    final callback = _onProcessStarted;
    _onProcessStarted = null;
    callback?.call();
  }

  void _handleStartFailure(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_startFailed) return;
    _startFailed = true;
    _launchPhase = _LaunchPhase.failed;
    _spawnRequested = false;
    _cancelStartupTimers();
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _onProcessStarted = null;
    _onProcessExited = null;
    _transport?.close();
    _transport = null;
    _startupExecutable = null;
    appLogger.e('[terminal] $message', error: error, stackTrace: stackTrace);
    write('\r\n$message\r\n');
    _onProcessFailed?.call(message);
    _onProcessFailed = null;
  }

  void _teardownPtyState() {
    _spawnRequested = false;
    _pendingPtyResizeCols = null;
    _pendingPtyResizeRows = null;
    _cancelStartupTimers();
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _launchPhase = _LaunchPhase.idle;
    _startupExecutable = null;
    _onProcessStarted = null;
    activityTracker.reset();
    _userTurnActive = false;
  }

  void writeToPty(String text) {
    if (_transportReadyForIo && _transport != null) {
      _transport!.write(Uint8List.fromList(utf8.encode(text)));
    }
  }

  /// [TerminalTextSink]: append raw text at the cursor with no submit.
  @override
  void appendText(String text) => writeToPty(text);

  /// [TerminalTextSink]: stage text in a full-screen TUI without submitting.
  @override
  Future<void> pasteWithoutSubmit(String text) => pasteText(text);

  /// Insert [text] into a full-screen TUI's input box via bracketed paste,
  /// sending no CR so it is staged (e.g. a dropped file path) but not submitted.
  /// Serialized through [_ptySubmitChain] so it never interleaves with a
  /// [submitFullScreenInput] burst's standalone CR.
  Future<void> pasteText(String text) {
    final next = _ptySubmitChain.then((_) async {
      writeToPty('\x1B[200~$text\x1B[201~');
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  void writeln(String text) {
    markUserTurnStarted();
    writeToPty('$text\r');
  }

  /// Submit a line to a full-screen TUI CLI (e.g. Claude Code) on the alternate
  /// screen, where [writeln]'s single `text\r` write does not submit.
  ///
  /// Claude Code's Ink input box coalesces one write of `text\r` into a paste
  /// burst, so the trailing CR becomes a literal newline and nothing is sent.
  /// Mirror Claude Code's own child-PTY injection: write the text wrapped in
  /// bracketed-paste markers, let the input box settle, then write a CR on its
  /// own so it registers as a discrete Enter. Submissions are serialized through
  /// [_ptySubmitChain] so overlapping injections never interleave their CR.
  Future<void> submitFullScreenInput(String text) {
    markUserTurnStarted();
    final pasteSettleDelay = (_runtimeTarget?.namespace.isSsh ?? false)
        ? const Duration(milliseconds: 500)
        : _fullScreenSubmitDelay;
    final next = _ptySubmitChain.then((_) async {
      writeToPty('\x1B[200~$text\x1B[201~');
      await Future<void>.delayed(pasteSettleDelay);
      writeToPty('\r');
    });
    // Keep the chain healthy if a write throws so later injections still run.
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  /// Submit whatever is already sitting in the input box with a standalone CR,
  /// without re-typing any text. Used to retry a doorbell whose earlier CR was
  /// swallowed by the full-screen input box's paste coalescing — re-pasting the
  /// whole notice would just stack duplicate copies in the box. Serialized
  /// through the same [_ptySubmitChain] so it never interleaves with a paste.
  Future<void> submitPendingCr() {
    final next = _ptySubmitChain.then((_) async {
      writeToPty('\r');
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  /// String entry point for synthetic engine writes (failure/exit notices and
  /// the public [write]). PTY output uses [_feedPtyBytes] directly.
  void _writeOutput(String text) =>
      _feedPtyBytes(Uint8List.fromList(utf8.encode(text)));

  static bool _looksLikeExecFailure(String text) {
    return text.contains('execvp:') ||
        text.contains('No such file or directory') ||
        text.contains('没有那个文件或目录');
  }

  /// Claude Code (and similar CLIs) print a fatal config/permission error then
  /// exit 1 — often after the first PTY bytes so [_confirmProcessStarted] already
  /// ran. Detect early and route through [_handleStartFailure] (logs + UI).
  static bool _looksLikeCliStartupFailure(String text) {
    return text.contains('matches no known tool') ||
        text.contains('cannot be used with root/sudo privileges') ||
        text.contains('Permission deny rule');
  }

  String _launchFailureMessage(String executable) {
    final cliName = CliExecutableValidator.cliDisplayName(executable);
    if (!validateLaunch) {
      return '[无法启动远端 $cliName: "$executable"。\n'
          '  请检查 SSH Profile 中的远端路径、PATH、工作目录和执行权限。]';
    }
    return _execFailureMessage(executable);
  }

  static String _execFailureMessage(String executable) {
    final cliName = CliExecutableValidator.cliDisplayName(executable);
    return CliExecutableValidator.validateLaunch(
          executable: executable,
          workingDirectory: '',
        ) ??
        '[无法启动 $cliName: 未找到可执行文件 "$executable"。\n'
            '  请在「设置 → 会话」中配置 $cliName CLI 的绝对路径，'
            '或确保其已在 PATH 中（从文件管理器启动 AppImage 时 PATH 可能很短）。]';
  }

  void disconnect() {
    _transportStartGeneration++;
    _startFailed = false;
    _spawnRequested = false;
    _teardownPtyState();
    _onProcessFailed = null;
    _onProcessExited = null;
    _ptyEnvironment = null;
    _firstUserLineCapture = null;
    _everyUserLineCapture = null;
    _busUserLineCapture = null;
    _engineOutputSubscription?.cancel();
    _engineOutputSubscription = null;
    _transport?.close();
    _transport = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
    _disposeLinkProviders();
    engine.dispose();
    unawaited(_parkedSubmissions.close());
  }

  /// Full process environment for [Pty.start], including OSC 8 identity hints.
  ///
  /// [inheritHostEnvironment] is true for local/WSL PTY (PATH, locale, …).
  /// SSH remote launches must pass false so the control-plane host's proxy and
  /// API endpoint env vars are not exported onto the work machine.
  static Map<String, String> buildPtyEnvironment(
    Map<String, String>? environment, {
    int? themeBackground,
    bool inheritHostEnvironment = true,
  }) {
    final merged = <String, String>{
      if (inheritHostEnvironment) ...Platform.environment,
      if (environment != null) ...environment,
    };
    PtyLaunchEnvironment.applyHyperlinkIdentity(merged);
    if (themeBackground != null) {
      PtyLaunchEnvironment.applyColorScheme(
        merged,
        background: themeBackground,
      );
    }
    if (Platform.isWindows) {
      final path = merged['Path'] ?? merged['PATH'];
      if (path != null && path.isNotEmpty) {
        merged['PATH'] = path;
      }
    }
    return merged;
  }

  static Future<TerminalTransport> _defaultTransportStarter(
    String executable, {
    required List<String> arguments,
    required String workingDirectory,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async {
    final spawnExecutable = CliToolLocator.resolveSpawnExecutable(executable);
    final pty = Pty.start(
      spawnExecutable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      columns: columns,
      rows: rows,
      environment: environment,
    );
    appLogger.d("Pty started");
    return LocalPtyTransport(pty);
  }
}
