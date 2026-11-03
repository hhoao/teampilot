import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../terminal/terminal_transport.dart';
import '../../../terminal/terminal_transport_starter.dart';
import 'qoder_auth_store.dart';

/// Environment for the isolated login PTY: the CLI must read and write its
/// credentials under [configDir] only, never the user's global `~/.qoder`.
@visibleForTesting
Map<String, String> qoderLoginEnvironment({
  required String home,
  required String configDir,
  Map<String, String>? base,
  bool isWindows = false,
}) => {
  ...?base,
  'HOME': home,
  if (isWindows) 'USERPROFILE': home,
  'QODER_CONFIG_DIR': configDir,
  'TERM': 'xterm-256color',
  'COLORTERM': 'truecolor',
};

/// Embedded `qodercli login` terminal used to sign in / switch account.
///
/// Unlike the CodeBuddy TUI there is no slash command to drive: `login` is a
/// real subcommand that starts the browser flow on its own, so the dialog only
/// shows the PTY. The CLI runs with a **per-provider isolated `HOME` and
/// `QODER_CONFIG_DIR`** so credentials land in TeamPilot's login store rather
/// than the user's global `~/.qoder`. "Done" reports success back to the
/// provider action bar, which copies `<QODER_CONFIG_DIR>/.auth` into the
/// provider store.
class QoderLoginDialog extends StatefulWidget {
  const QoderLoginDialog({
    required this.executable,
    required this.store,
    required this.providerId,
    this.arguments = const [],
    super.key,
  });

  final String executable;
  final QoderAuthStore store;
  final String providerId;
  final List<String> arguments;

  @override
  State<QoderLoginDialog> createState() => _QoderLoginDialogState();
}

class _QoderLoginDialogState extends State<QoderLoginDialog> {
  late final TerminalEngine _engine;
  TerminalTransport? _transport;
  StreamSubscription<Uint8List>? _outputSub;
  StreamSubscription<Uint8List>? _engineSub;
  String? _error;
  var _starting = true;
  var _exited = false;
  var _signedIn = false;

  @override
  void initState() {
    super.initState();
    _engine = TerminalEngine(config: TerminalConfig.defaults());
    unawaited(_start());
  }

  Future<void> _start() async {
    _closeTransport();
    if (!mounted) return;
    setState(() {
      _starting = true;
      _exited = false;
      _signedIn = false;
      _error = null;
    });
    try {
      final store = widget.store;
      final home = store.loginHome(widget.providerId);
      final configDir = store.loginConfigDir(widget.providerId);
      final workingDirectory = store.loginWorkspace(widget.providerId);
      await store.fs.ensureDir(home);
      await store.fs.ensureDir(configDir);
      await store.fs.ensureDir(workingDirectory);
      // Every attempt starts unauthenticated: a previous login's `.auth` must
      // not make this attempt look signed-in before the browser flow.
      await store.clearLoginAuth(widget.providerId);
      final transport = await defaultTransportStarter(
        widget.executable,
        arguments: widget.arguments,
        workingDirectory: workingDirectory,
        columns: 100,
        rows: 30,
        environment: qoderLoginEnvironment(
          home: home,
          configDir: configDir,
          base: Platform.environment,
          isWindows: Platform.isWindows,
        ),
      );
      if (!mounted) {
        transport.close();
        return;
      }
      _transport = transport;
      _outputSub = transport.output.listen(_engine.feed);
      _engineSub = _engine.output.listen(transport.write);
      _engine.onPtyResize = (columns, rows) => transport.resize(rows, columns);
      unawaited(
        transport.done.then((_) {
          // Ignore a superseded terminal (Relaunch closes the previous one).
          if (!identical(_transport, transport)) return;
          if (mounted) unawaited(_onExited());
        }),
      );
      setState(() => _starting = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '$error';
      });
    }
  }

  /// `qodercli login` exits once the browser flow completes, so an exit is not
  /// a failure by itself — check whether the isolated config dir now holds the
  /// `.auth` pair before showing the "sign in again" hint.
  Future<void> _onExited() async {
    final signedIn = await _hasLoginAuth();
    if (!mounted) return;
    setState(() {
      _exited = true;
      _signedIn = signedIn;
    });
  }

  Future<bool> _hasLoginAuth() async {
    final store = widget.store;
    final authDir = store.pathContext.join(
      store.loginConfigDir(widget.providerId),
      '.auth',
    );
    final user = await store.fs.stat(
      store.pathContext.join(authDir, QoderAuthStore.userFileName),
    );
    if (!user.isFile) return false;
    final machineId = await store.fs.stat(
      store.pathContext.join(authDir, QoderAuthStore.machineIdFileName),
    );
    return machineId.isFile;
  }

  void _closeTransport() {
    _outputSub?.cancel();
    _outputSub = null;
    _engineSub?.cancel();
    _engineSub = null;
    _engine.onPtyResize = null;
    _transport?.close();
    _transport = null;
  }

  @override
  void dispose() {
    _closeTransport();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final terminalHeight = (MediaQuery.sizeOf(context).height * 0.55).clamp(
      260.0,
      520.0,
    );
    return TpDialog(
      maxWidth: 960,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.qoderCredentialsLoginTitle),
          const SizedBox(height: 12),
          Text(
            l10n.qoderCredentialsLoginIntro,
            style: TpTextStyles.of(context).mutedSm,
          ),
          const SizedBox(height: 12),
          Container(
            height: terminalHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF101014),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: TerminalView(
                    _engine,
                    theme: TerminalTheme.defaults,
                    textStyle: TerminalStyle.defaults(),
                    preferGpuSurface: false,
                    autofocus: true,
                    padding: const EdgeInsets.all(8),
                    onPtyResize: (columns, rows) {
                      if (columns < kMinTerminalColumns ||
                          rows < kMinTerminalRows) {
                        return;
                      }
                      _transport?.resize(rows, columns);
                    },
                  ),
                ),
                if (_starting)
                  Center(
                    child: Text(
                      l10n.qoderCredentialsLoginStarting,
                      style: const TextStyle(color: Color(0xFFDDDDDD)),
                    ),
                  ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      l10n.qoderCredentialsLoginFailed(_error!),
                      style: const TextStyle(color: Color(0xFFFF7B72)),
                    ),
                  ),
              ],
            ),
          ),
          if (_signedIn) ...[
            const SizedBox(height: 8),
            Text(
              l10n.qoderCredentialsSignedIn,
              style: TpTextStyles.of(context).mutedSm,
            ),
          ] else if (_exited) ...[
            const SizedBox(height: 8),
            Text(
              l10n.qoderCredentialsLoginExited,
              style: TpTextStyles.of(context).mutedSm,
            ),
          ],
          const SizedBox(height: 16),
          TpDialogActions(
            children: [
              TpButton(
                variant: TpButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.qoderCredentialsCancel),
              ),
              TpButton(
                variant: TpButtonVariant.outline,
                onPressed: _starting ? null : () => unawaited(_start()),
                child: Text(l10n.qoderCredentialsRelaunch),
              ),
              TpButton(
                onPressed: _signedIn && !_starting
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(l10n.qoderCredentialsDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
