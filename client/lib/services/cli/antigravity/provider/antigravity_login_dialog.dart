import 'dart:async';
import 'dart:io' show Platform, Process;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/app_provider_config.dart';
import '../../../storage/home_storage.dart';
import '../../../terminal/terminal_transport.dart';
import '../../../terminal/terminal_transport_starter.dart';

/// Runs `agy models` in the login environment; true when it exits 0.
typedef AntigravityModelsProbe =
    Future<bool> Function({
      required String executable,
      required Map<String, String> environment,
      required String workingDirectory,
    });

Future<bool> runAgyModelsProbe({
  required String executable,
  required Map<String, String> environment,
  required String workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    const ['models'],
    environment: environment,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  ).timeout(const Duration(seconds: 60));
  return result.exitCode == 0;
}

/// Embedded interactive `agy` terminal used to sign in with a Google account.
///
/// The CLI runs with an isolated `HOME` and `GEMINI_HOME` per provider row so
/// its settings never touch the user's global Antigravity config. The OAuth
/// token itself lands in the OS keyring, which every Antigravity session and
/// official provider row shares. "Done" runs `agy models` to verify the
/// sign-in before closing, so it stays available after the CLI exits.
class AntigravityLoginDialog extends StatefulWidget {
  const AntigravityLoginDialog({
    required this.provider,
    required this.executable,
    required this.storage,
    this.verifyModels = runAgyModelsProbe,
    super.key,
  });

  final AppProviderConfig provider;
  final String executable;
  final HomeStorage storage;
  final AntigravityModelsProbe verifyModels;

  @override
  State<AntigravityLoginDialog> createState() => _AntigravityLoginDialogState();
}

class _AntigravityLoginDialogState extends State<AntigravityLoginDialog> {
  late final TerminalEngine _engine;
  TerminalTransport? _transport;
  StreamSubscription<Uint8List>? _outputSub;
  StreamSubscription<Uint8List>? _engineSub;
  String? _home;
  String? _workspace;
  String? _error;
  var _starting = true;
  var _exited = false;
  var _verifying = false;
  var _verifyFailed = false;

  @override
  void initState() {
    super.initState();
    _engine = TerminalEngine(config: TerminalConfig.defaults());
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final fs = widget.storage.fs;
      final pc = fs.pathContext;
      final root = pc.join(
        widget.storage.paths.basePath,
        'cli-login',
        'antigravity',
        _safeSegment(widget.provider.id),
      );
      final home = pc.join(root, 'home');
      final workspace = pc.join(root, 'workspace');
      await fs.ensureDir(home);
      await fs.ensureDir(workspace);
      _home = home;
      _workspace = workspace;

      final transport = await defaultTransportStarter(
        widget.executable,
        arguments: const [],
        workingDirectory: workspace,
        columns: 100,
        rows: 30,
        environment: _environment(home),
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
          if (mounted) setState(() => _exited = true);
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

  Map<String, String> _environment(String home) {
    final pc = widget.storage.fs.pathContext;
    return {
      ...Platform.environment,
      'HOME': home,
      if (Platform.isWindows) 'USERPROFILE': home,
      'GEMINI_HOME': pc.join(home, '.gemini'),
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
    };
  }

  Future<void> _done() async {
    final home = _home;
    final workspace = _workspace;
    if (home == null || workspace == null || _verifying) return;
    setState(() {
      _verifying = true;
      _verifyFailed = false;
    });
    final ok = await _verifySafely(home, workspace);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _verifying = false;
      _verifyFailed = true;
    });
  }

  Future<bool> _verifySafely(String home, String workspace) async {
    try {
      return await widget.verifyModels(
        executable: widget.executable,
        environment: _environment(home),
        workingDirectory: workspace,
      );
    } on Object {
      return false;
    }
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    _engineSub?.cancel();
    _engine.onPtyResize = null;
    _transport?.close();
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
    final canDone = !_verifying && !_starting && _error == null;
    return TpDialog(
      maxWidth: 960,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.antigravityCredentialsLoginTitle),
          const SizedBox(height: 12),
          Text(
            l10n.antigravityCredentialsLoginIntro,
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
                      l10n.antigravityCredentialsLoginStarting,
                      style: const TextStyle(color: Color(0xFFDDDDDD)),
                    ),
                  ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      l10n.antigravityCredentialsLoginFailed(_error!),
                      style: const TextStyle(color: Color(0xFFFF7B72)),
                    ),
                  ),
              ],
            ),
          ),
          if (_exited) ...[
            const SizedBox(height: 8),
            Text(
              l10n.antigravityCredentialsLoginExited,
              style: TpTextStyles.of(context).mutedSm,
            ),
          ],
          if (_verifyFailed) ...[
            const SizedBox(height: 8),
            Text(
              l10n.antigravityCredentialsLoginVerifyFailed,
              style: const TextStyle(color: Color(0xFFFF7B72)),
            ),
          ],
          const SizedBox(height: 16),
          TpDialogActions(
            children: [
              TpButton(
                variant: TpButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.antigravityCredentialsCancel),
              ),
              TpButton(
                onPressed: canDone ? () => unawaited(_done()) : null,
                child: Text(l10n.antigravityCredentialsDone),
              ),
              if (_error != null)
                TpButton(
                  variant: TpButtonVariant.outline,
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _starting = true;
                    });
                    unawaited(_start());
                  },
                  child: Text(l10n.antigravityCredentialsRetry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _safeSegment(String id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
