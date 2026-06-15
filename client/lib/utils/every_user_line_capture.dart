/// Buffers raw terminal keystrokes and fires on every user-submitted line (Enter).
///
/// Unlike [FirstUserLineCapture], this captures every line, not just the first.
class EveryUserLineCapture {
  EveryUserLineCapture(this._onSubmitted);

  final void Function(String line) _onSubmitted;
  final StringBuffer _buffer = StringBuffer();
  _EveryInputMode _mode = _EveryInputMode.normal;

  void feed(String data) {
    if (data.isEmpty) return;
    for (final codeUnit in data.codeUnits) {
      _feedCodeUnit(codeUnit);
    }
  }

  void _feedCodeUnit(int codeUnit) {
    if (_mode == _EveryInputMode.normal) {
      _feedNormal(codeUnit);
      return;
    }
    if (_mode == _EveryInputMode.afterEsc) {
      _feedAfterEsc(codeUnit);
      return;
    }
    if (_mode == _EveryInputMode.csi) {
      if (_isCsiFinal(codeUnit)) _mode = _EveryInputMode.normal;
      return;
    }
    if (_mode == _EveryInputMode.ss3) {
      _mode = _EveryInputMode.normal;
      return;
    }
    if (_mode == _EveryInputMode.osc) {
      _feedOsc(codeUnit);
      return;
    }
    if (_mode == _EveryInputMode.oscEsc) {
      _mode =
          codeUnit == 0x5c ? _EveryInputMode.normal : _EveryInputMode.osc;
    }
  }

  void _feedNormal(int codeUnit) {
    if (codeUnit == 0x1b) {
      _mode = _EveryInputMode.afterEsc;
      return;
    }
    if (codeUnit == 0x0d || codeUnit == 0x0a) {
      _submit();
      return;
    }
    if (codeUnit == 0x7f || codeUnit == 0x08) {
      _backspace();
      return;
    }
    if (codeUnit < 0x20 && codeUnit != 0x09) return;
    _buffer.writeCharCode(codeUnit);
  }

  void _feedAfterEsc(int codeUnit) {
    if (codeUnit == 0x5b) {
      _mode = _EveryInputMode.csi;
      return;
    }
    if (codeUnit == 0x4f) {
      _mode = _EveryInputMode.ss3;
      return;
    }
    if (codeUnit == 0x5d) {
      _mode = _EveryInputMode.osc;
      return;
    }
    if (_isCsiFinal(codeUnit)) {
      _mode = _EveryInputMode.normal;
      return;
    }
    _mode = _EveryInputMode.normal;
  }

  void _feedOsc(int codeUnit) {
    if (codeUnit == 0x07) {
      _mode = _EveryInputMode.normal;
      return;
    }
    if (codeUnit == 0x1b) {
      _mode = _EveryInputMode.oscEsc;
    }
  }

  static bool _isCsiFinal(int codeUnit) =>
      codeUnit >= 0x40 && codeUnit <= 0x7e;

  void _backspace() {
    final text = _buffer.toString();
    if (text.isEmpty) return;
    _buffer
      ..clear()
      ..write(text.substring(0, text.length - 1));
  }

  void _submit() {
    final line = _sanitizeCapturedLine(_buffer.toString());
    _buffer.clear();
    if (line.isEmpty) return;
    _onSubmitted(line);
  }

  /// Strips any CSI/escape fragments that leaked into the buffer.
  static String _sanitizeCapturedLine(String raw) {
    return raw
        .replaceAll(RegExp(r'\x1b\[[\x30-\x3f\x20-\x2f]*[\x40-\x7e]'), '')
        .replaceAll(RegExp(r'\[[\x30-\x3f\x20-\x2f]*[\x40-\x7e]'), '')
        .replaceAll(RegExp(r'\x1b.'), '')
        .trim();
  }
}

enum _EveryInputMode { normal, afterEsc, csi, ss3, osc, oscEsc }
