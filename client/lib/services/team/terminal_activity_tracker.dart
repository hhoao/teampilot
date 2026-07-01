import 'dart:typed_data';

/// Heuristic workload signal from PTY output (FlashskyAI v1).
///
/// Ignores the initial boot burst: [isWorking] stays false until output has
/// been quiet for [idleAfter], then tracks activity the same way.
///
/// [notePtyBytes] dedupes repaint noise on the PTY hot path with a single-pass
/// FNV hash of the chunk's **last visible line** (ANSI stripped, block glyphs
/// skipped). No regex, no intermediate [String], O(n) bytes only.
///
/// Mixed teams: [isQuietAfterTurnPtyActivity] is true when the visible
/// fingerprint has been unchanged for [idleAfter] since [latchTurnQuietBaseline]
/// or since the last fingerprint change this turn (no PTY bytes also counts).
/// Also feeds the native single-CLI path and simple-mode `_tickIdleWatch`.
class TerminalActivityTracker {
  TerminalActivityTracker({
    this.idleAfter = const Duration(milliseconds: 2500),
  });

  final Duration idleAfter;

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
  /// turn latch or since the last fingerprint change (zero PTY bytes included).
  bool get isQuietAfterTurnPtyActivity {
    final since = _fingerprintStableSince ?? _turnLatchedAt;
    if (since == null) return false;
    return DateTime.now().difference(since) >= idleAfter;
  }

  /// Records PTY output; skips [noteOutput] when the fingerprint hash is unchanged.
  void notePtyBytes(List<int> bytes, [DateTime? at]) {
    if (bytes.isEmpty) return;
    final raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final now = at ?? DateTime.now();
    final hash = visiblePtyFingerprintHash(raw);

    if (!_turnPtyObserved) {
      _beginTurnFingerprint(hash, raw, now);
      return;
    }

    final cached = _lastRawChunk;
    if (cached != null &&
        raw.length == cached.length &&
        _bytesEqual(raw, cached)) {
      return;
    }

    if (hash == _lastFingerprintHash) return;

    _lastFingerprintHash = hash;
    _lastRawChunk = raw.length <= _rawFastPathMaxBytes
        ? Uint8List.fromList(raw)
        : null;
    _fingerprintStableSince = now;
    noteOutput(now);
  }

  void _beginTurnFingerprint(int hash, Uint8List raw, DateTime now) {
    _turnPtyObserved = true;
    _lastFingerprintHash = hash;
    _lastRawChunk = raw.length <= _rawFastPathMaxBytes
        ? Uint8List.fromList(raw)
        : null;
    _fingerprintStableSince = now;
    noteOutput(now);
  }

  /// Single-pass FNV-1a over the chunk's last line: strips ESC/CSI/OSC, skips
  /// `\\r` and UTF-8 block elements (U+2580–U+259F). Exposed for tests.
  static int visiblePtyFingerprintHash(List<int> bytes) {
    var lineHash = _fnvOffsetBasis;
    var i = 0;
    var afterEsc = false;
    var inCsi = false;
    var inOsc = false;

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
        lineHash = _fnvOffsetBasis;
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

      lineHash = _fnv1a(lineHash, b);
      i++;
    }
    return lineHash;
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
    final bootAt = _bootOutputAt;
    if (bootAt == null) {
      _armed = true;
      return;
    }
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
