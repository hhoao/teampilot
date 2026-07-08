import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/links/terminal_link_provider.dart';

import 'package:flutter_alacritty/links/url_link_provider.dart';

import '../storage/app_storage.dart';
import '../io/filesystem.dart';
import 'file_path_link_provider.dart';
import 'terminal_uri_opener.dart';

/// OSC 7 link providers for a [TerminalSession]'s [TerminalView].
final class TerminalSessionLinkProviders {
  TerminalSessionLinkProviders({
    required this.engine,
    Filesystem? fs,
  }) : _fs = fs ?? AppStorage.fs;

  final TerminalEngine engine;
  final Filesystem _fs;

  List<TerminalLinkProvider>? _providers;
  ValueNotifier<String?>? _osc7Cwd;

  List<TerminalLinkProvider> build(String launchCwd) {
    return _providers ??= _create(launchCwd);
  }

  /// Drops cached providers so the next [build] uses the current launch cwd.
  void invalidate() => dispose();

  void dispose() {
    final providers = _providers;
    if (providers == null) return;
    engine.workingDir.removeListener(_syncOsc7Cwd);
    for (final p in providers) {
      p.dispose();
    }
    _osc7Cwd?.dispose();
    _osc7Cwd = null;
    _providers = null;
  }

  List<TerminalLinkProvider> _create(String launchCwd) {
    final cwd = ValueNotifier<String?>(parseOsc7Cwd(engine.workingDir.value));
    engine.workingDir.addListener(_syncOsc7Cwd);
    _osc7Cwd = cwd;
    return [
      UrlLinkProvider(),
      FilePathLinkProvider(fs: _fs, launchCwd: launchCwd, cwd: cwd),
    ];
  }

  void _syncOsc7Cwd() =>
      _osc7Cwd?.value = parseOsc7Cwd(engine.workingDir.value);

  /// Parses an OSC 7 working-directory report (`file://host/path`) into a local
  /// directory path, or `null` when it is empty, remote, or unparseable.
  static String? parseOsc7Cwd(String raw) {
    if (raw.trim().isEmpty) return null;
    return TerminalUriOpener.resolveLocalFilePath(raw);
  }
}
