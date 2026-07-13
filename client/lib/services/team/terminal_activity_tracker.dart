import 'dart:typed_data';

typedef _VisibleTailScan = ({int hash, bool hasVisibleContent});

/// Heuristic workload signal from PTY output (FlashskyAI v1).
///
/// **Boot frame** ([isBootFrameReady]): meaningful visible PTY content in the
/// trailing-line window, then fingerprint unchanged for [bootQuietAfter].
/// Latches true on first success until [reset].
///
/// **Turn workload** ([isWorking]): after the longer [idleAfter] boot-quiet
/// window, tracks recent PTY activity for working/idle during a turn.
///
/// [notePtyBytes] dedupes repaint noise on the PTY hot path with a single-pass
/// FNV hash of the chunk's **last [fingerprintTailLines] visible lines** (ANSI
/// stripped, block glyphs skipped). No regex, no intermediate [String], O(n)
/// bytes only.
///
/// Mixed teams: [isQuietAfterTurnPtyActivity] is true when the visible
/// fingerprint has been unchanged for [idleAfter] since the last fingerprint
/// change this turn ([notePtyBytes] at least once). No PTY bytes → not quiet.
/// Also feeds the native single-CLI path and simple-mode `_tickIdleWatch`.
class TerminalActivityTracker {
  TerminalActivityTracker({
    this.idleAfter = const Duration(milliseconds: 2500),
    this.bootQuietAfter = const Duration(milliseconds: 500),
    this.fingerprintTailLines = defaultFingerprintTailLines,
  }) : assert(fingerprintTailLines >= 1);

  /// Default tail window — covers prompt + status rows in full-screen TUIs.
  static const int defaultFingerprintTailLines = 8;

  /// Turn-level working/idle quiet window (post-boot).
  final Duration idleAfter;

  /// Boot frame stable quiet window (visible output + fingerprint unchanged).
  final Duration bootQuietAfter;

  /// How many trailing visible lines feed the PTY fingerprint hash.
  final int fingerprintTailLines;

  static const int _fnvOffsetBasis = 0x811C9DC5;
  static const int _fnvPrime = 0x01000193;

  /// Cap raw-byte fast-path cache (full-screen repaints are usually < 4 KiB).
  static const int _rawFastPathMaxBytes = 4096;

  bool _armed = false;
  DateTime? _lastActivity;
  DateTime? _bootOutputAt;
  int? _lastFingerprintHash;
  Uint8List? _lastRawChunk;

  /// At least one [notePtyBytes] since [latchTurnQuietBaseline] in this turn.
  bool _turnPtyObserved = false;

  /// When the current fingerprint hash was first seen or last changed this turn.
  DateTime? _fingerprintStableSince;

  /// When [latchTurnQuietBaseline] ran for the current bus/simple turn.
  DateTime? _turnLatchedAt;

  /// At least one [notePtyBytes] since [reset] (boot/session frame tracking).
  bool _bootPtyObserved = false;

  /// Non-whitespace visible glyphs seen in the tail window since [reset].
  bool _bootVisibleContentSeen = false;

  /// Once the boot frame has been stable, stay ready until [reset] — avoids
  /// presence flicker when startup TUI keeps repainting after the first quiet
  /// window (spinners, welcome banners, status rows).
  bool _bootFrameLatched = false;

  /// True once meaningful visible content has appeared in the tail window and
  /// the fingerprint has been unchanged for [bootQuietAfter].
  /// Latches true on first success and does not revert until [reset].
  bool get isBootFrameReady {
    if (_bootFrameLatched) return true;
    if (!_bootPtyObserved || !_bootVisibleContentSeen) return false;
    final since = _fingerprintStableSince;
    if (since == null) return false;
    if (DateTime.now().difference(since) >= bootQuietAfter) {
      _bootFrameLatched = true;
      return true;
    }
    return false;
  }

  /// Compact boot-gate dump for inject readiness diagnostics.
  String get bootFrameDebugSummary {
    final since = _fingerprintStableSince;
    final stableMs = since == null
        ? null
        : DateTime.now().difference(since).inMilliseconds;
    return 'latched=$_bootFrameLatched '
        'ptyObserved=$_bootPtyObserved '
        'visible=$_bootVisibleContentSeen '
        'stableMs=$stableMs '
        'needMs=${bootQuietAfter.inMilliseconds}';
  }

  void markActive([DateTime? at]) {
    noteOutput(at);
  }

  /// Clears per-turn fingerprint baseline (mixed/simple bus turn rising edge).
  void latchTurnQuietBaseline([DateTime? at]) {
    _turnPtyObserved = false;
    _fingerprintStableSince = null;
    _turnLatchedAt = at ?? DateTime.now();
  }

  /// True when the fingerprint has been unchanged for [idleAfter] since the
  /// last fingerprint change this turn. Requires at least one [notePtyBytes]
  /// so MCP-only gaps (no PTY yet / between tools) do not false-trigger quiet.
  bool get isQuietAfterTurnPtyActivity {
    if (!_turnPtyObserved) return false;
    final since = _fingerprintStableSince;
    if (since == null) return false;
    return DateTime.now().difference(since) >= idleAfter;
  }

  /// Records PTY output; skips [noteOutput] when the fingerprint hash is unchanged.
  void notePtyBytes(List<int> bytes, [DateTime? at]) {
    if (bytes.isEmpty) return;
    final raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final now = at ?? DateTime.now();
    final scan = _scanVisibleTail(raw, tailLines: fingerprintTailLines);
    final hash = scan.hash;

    if (!_turnPtyObserved) {
      _beginTurnFingerprint(scan, raw, now);
      return;
    }

    final cached = _lastRawChunk;
    if (cached != null &&
        raw.length == cached.length &&
        _bytesEqual(raw, cached)) {
      return;
    }

    if (hash == _lastFingerprintHash) return;

    _noteBootPtyObserved(scan.hasVisibleContent);
    _lastFingerprintHash = hash;
    _lastRawChunk = raw.length <= _rawFastPathMaxBytes
        ? Uint8List.fromList(raw)
        : null;
    _fingerprintStableSince = now;
    noteOutput(now);
  }

  void _beginTurnFingerprint(
    _VisibleTailScan scan,
    Uint8List raw,
    DateTime now,
  ) {
    _noteBootPtyObserved(scan.hasVisibleContent);
    _turnPtyObserved = true;
    _lastFingerprintHash = scan.hash;
    _lastRawChunk = raw.length <= _rawFastPathMaxBytes
        ? Uint8List.fromList(raw)
        : null;
    _fingerprintStableSince = now;
    noteOutput(now);
  }

  void _noteBootPtyObserved(bool hasVisibleContent) {
    _bootPtyObserved = true;
    if (hasVisibleContent) _bootVisibleContentSeen = true;
  }

  /// Single-pass scan of the chunk's last [tailLines] visible lines: strips
  /// ESC/CSI/OSC, skips `\\r` and UTF-8 block elements (U+2580–U+259F).
  static _VisibleTailScan _scanVisibleTail(
    List<int> bytes, {
    int tailLines = defaultFingerprintTailLines,
  }) {
    assert(tailLines >= 1);
    final window = <int>[];
    final windowVisible = <bool>[];
    var lineHash = _fnvOffsetBasis;
    var lineHasVisible = false;
    var i = 0;
    var afterEsc = false;
    var inCsi = false;
    var inOsc = false;

    void pushLine(int hash, bool visible) {
      window.add(hash);
      windowVisible.add(visible);
      if (window.length > tailLines) {
        window.removeAt(0);
        windowVisible.removeAt(0);
      }
    }

    void flushCurrentLine() {
      pushLine(lineHash, lineHasVisible);
      lineHash = _fnvOffsetBasis;
      lineHasVisible = false;
    }

    while (i < bytes.length) {
      final b = bytes[i];

      if (inOsc) {
        if (b == 0x07) {
          inOsc = false;
        } else if (b == 0x1b && i + 1 < bytes.length && bytes[i + 1] == 0x5c) {
          inOsc = false;
          i++; // ST backslash
        }
        i++;
        continue;
      }

      if (inCsi) {
        if (b >= 0x40 && b <= 0x7e) inCsi = false;
        i++;
        continue;
      }

      if (afterEsc) {
        afterEsc = false;
        if (b == 0x5b) {
          inCsi = true;
        } else if (b == 0x5d) {
          inOsc = true;
        }
        i++;
        continue;
      }

      if (b == 0x1b) {
        afterEsc = true;
        i++;
        continue;
      }

      if (b == 0x0d) {
        i++;
        continue;
      }

      if (b == 0x0a) {
        flushCurrentLine();
        i++;
        continue;
      }

      // Block elements ▀▄█░ (U+2580–U+259F) — spinner noise.
      if (b == 0xe2 && i + 2 < bytes.length && bytes[i + 1] == 0x96) {
        final b2 = bytes[i + 2];
        if (b2 >= 0x80 && b2 <= 0xbf) {
          i += 3;
          continue;
        }
      }

      if (_isMeaningfulVisibleByte(b)) lineHasVisible = true;
      lineHash = _fnv1a(lineHash, b);
      i++;
    }

    if (lineHash != _fnvOffsetBasis) {
      pushLine(lineHash, lineHasVisible);
    }

    return (
      hash: _combineLineHashes(window),
      hasVisibleContent: windowVisible.any((visible) => visible),
    );
  }

  static bool _isMeaningfulVisibleByte(int b) {
    if (b == 0x09 || b == 0x20) return false;
    if (b >= 0x21 && b <= 0x7e) return true;
    return b >= 0x80;
  }

  /// FNV hash of trailing visible lines. Exposed for tests.
  static int visiblePtyFingerprintHash(
    List<int> bytes, {
    int tailLines = defaultFingerprintTailLines,
  }) => _scanVisibleTail(bytes, tailLines: tailLines).hash;

  static int _combineLineHashes(List<int> lineHashes) {
    if (lineHashes.isEmpty) return _fnvOffsetBasis;
    var combined = _fnvOffsetBasis;
    for (final line in lineHashes) {
      combined = _fnv1a(combined, line & 0xFF);
      combined = _fnv1a(combined, (line >> 8) & 0xFF);
      combined = _fnv1a(combined, (line >> 16) & 0xFF);
      combined = _fnv1a(combined, (line >> 24) & 0xFF);
    }
    return combined;
  }

  void noteOutput([DateTime? at]) {
    final now = at ?? DateTime.now();
    if (_armed) {
      _lastActivity = now;
    } else {
      _bootOutputAt = now;
    }
  }

  void reset() {
    _armed = false;
    _lastActivity = null;
    _bootOutputAt = null;
    _lastFingerprintHash = null;
    _lastRawChunk = null;
    _turnPtyObserved = false;
    _fingerprintStableSince = null;
    _turnLatchedAt = null;
    _bootPtyObserved = false;
    _bootVisibleContentSeen = false;
    _bootFrameLatched = false;
  }

  /// Tests: latch a stable boot frame without waiting real time.
  void latchBootFrameReadyForTest([DateTime? at]) {
    final now = at ?? DateTime.now();
    _bootPtyObserved = true;
    _bootVisibleContentSeen = true;
    _bootFrameLatched = true;
    _turnPtyObserved = true;
    _fingerprintStableSince = now.subtract(bootQuietAfter);
    _armed = true;
    _lastActivity = now;
    _bootOutputAt = null;
  }

  /// True when output arrived within [idleAfter] after the boot quiet window.
  bool get isWorking {
    _tryArmAfterBootQuiet();
    if (!_armed) return false;
    final last = _lastActivity;
    if (last == null) return false;
    return DateTime.now().difference(last) < idleAfter;
  }

  void _tryArmAfterBootQuiet() {
    if (_armed) return;
    // Stay unarmed until we have seen boot output and it has been quiet for
    // [idleAfter]. Reading [isWorking] before the first PTY chunk (common right
    // after [reset] on connect) must not arm — otherwise the startup banner is
    // recorded as post-boot activity and falsely lights session-working.
    final bootAt = _bootOutputAt;
    if (bootAt == null) return;
    if (DateTime.now().difference(bootAt) >= idleAfter) {
      _armed = true;
      _bootOutputAt = null;
    }
  }

  static int _fnv1a(int hash, int byte) {
    hash = (hash ^ byte) & 0xFFFFFFFF;
    return (hash * _fnvPrime) & 0xFFFFFFFF;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
