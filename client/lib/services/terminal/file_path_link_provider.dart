import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/links/terminal_link_provider.dart';

import '../io/filesystem.dart';
import 'terminal_uri_opener.dart';

/// Detects file paths in terminal output and makes only existing files
/// clickable via async filesystem validation. Injected into TerminalView as a
/// [TerminalLinkProvider]. Path semantics + filesystem validation live here in
/// TeamPilot, keeping flutter_alacritty IO-free.
class FilePathLinkProvider extends TerminalLinkProvider {
  FilePathLinkProvider({
    required this.fs,
    required this.launchCwd,
    ValueListenable<String?>? cwd,
  }) : _cwdListenable = cwd {
    _cwdListenable?.addListener(_onCwdChanged);
  }

  final Filesystem fs;
  final String launchCwd;
  final ValueListenable<String?>? _cwdListenable;

  // Matches an optional anchor (./ ../ / or a Windows drive), then path-ish
  // segments, then an optional :line[:col] suffix.
  static final RegExp _pattern = RegExp(
    r'(?:\.{1,2}/|/|[A-Za-z]:[\\/])?'
    r'[\w.\-]+(?:[\\/][\w.\-]+)*'
    r'(?::\d+(?::\d+)?)?',
  );

  // Cache: keys are "$cwd $payload" strings.
  final Set<String> _confirmed = {};
  final Map<String, DateTime> _negativeUntil = {};
  final Set<String> _inFlight = {};

  static const Duration _negativeTtl = Duration(seconds: 5);
  static const int _maxConcurrent = 8;

  String _cwd() {
    final live = _cwdListenable?.value;
    return (live != null && live.isNotEmpty) ? live : launchCwd;
  }

  void _onCwdChanged() {
    _negativeUntil.clear();
    _inFlight.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _cwdListenable?.removeListener(_onCwdChanged);
    super.dispose();
  }

  String _key(String payload) => '${_cwd()} $payload';

  String _filePart(String payload) =>
      TerminalUriOpener.stripLineSuffix(payload);

  @override
  bool isEnabled(LinkSpan span) => _confirmed.contains(_key(span.payload));

  @override
  Iterable<LinkSpan> scan(String lineText) sync* {
    for (final m in _pattern.allMatches(lineText)) {
      final raw = m.group(0)!;
      if (!_looksLikePath(raw)) continue;
      _maybeValidate(raw);
      yield LinkSpan(start: m.start, end: m.end, payload: raw);
    }
  }

  void _maybeValidate(String payload) {
    final key = _key(payload);
    if (_confirmed.contains(key) || _inFlight.contains(key)) return;
    final neg = _negativeUntil[key];
    if (neg != null && DateTime.now().isBefore(neg)) return;
    if (_inFlight.length >= _maxConcurrent) return; // best-effort; next scan retries
    _inFlight.add(key);
    unawaited(_validate(key, payload));
  }

  Future<void> _validate(String key, String payload) async {
    try {
      final resolved = TerminalUriOpener.resolveLocalFilePath(
        _filePart(payload),
        workingDirectory: _cwd(),
      );
      if (resolved == null) {
        _recordNegative(key);
        return;
      }
      final stat = await fs.stat(resolved);
      if (stat.exists && stat.isFile) {
        _confirmed.add(key);
        notifyListeners();
      } else {
        _recordNegative(key);
      }
    } catch (_) {
      _recordNegative(key);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Records a TTL'd negative result, evicting already-expired entries first so
  /// the map stays bounded over a long session (it only holds tokens that
  /// failed within the last [_negativeTtl]).
  void _recordNegative(String key) {
    final now = DateTime.now();
    _negativeUntil.removeWhere((_, expiry) => now.isAfter(expiry));
    _negativeUntil[key] = now.add(_negativeTtl);
  }

  /// Shape heuristic to cut obvious non-paths before the (later) fs check.
  bool _looksLikePath(String s) {
    final core = s.split(':').first; // ignore :line[:col] for the shape test
    // Any separator => path-shaped (covers ./ ../ absolute and multi-segment).
    if (core.contains('/') || core.contains(r'\')) return true;
    // Single token: require a real file extension, and reject version-ish runs.
    final ext = RegExp(r'\.[A-Za-z][A-Za-z0-9]{0,8}$');
    return ext.hasMatch(core) && !RegExp(r'^\d+(\.\d+)+$').hasMatch(core);
  }
}
