/// Buffers raw terminal keystrokes until the user submits their first line (Enter).
class FirstUserLineCapture {
  FirstUserLineCapture(this._onSubmitted);

  final void Function(String line) _onSubmitted;
  final StringBuffer _buffer = StringBuffer();
  var _completed = false;
  _InputMode _mode = _InputMode.normal;

  bool get isCompleted => _completed;

  void feed(String data) {
    if (_completed || data.isEmpty) return;
    for (final codeUnit in data.codeUnits) {
      if (_completed) return;
      _feedCodeUnit(codeUnit);
    }
  }

  void _feedCodeUnit(int codeUnit) {
    if (_mode == _InputMode.normal) {
      _feedNormal(codeUnit);
      return;
    }
    if (_mode == _InputMode.afterEsc) {
      _feedAfterEsc(codeUnit);
      return;
    }
    if (_mode == _InputMode.csi) {
      if (_isCsiFinal(codeUnit)) _mode = _InputMode.normal;
      return;
    }
    if (_mode == _InputMode.ss3) {
      _mode = _InputMode.normal;
      return;
    }
    if (_mode == _InputMode.osc) {
      _feedOsc(codeUnit);
      return;
    }
    if (_mode == _InputMode.oscEsc) {
      _mode = codeUnit == 0x5c ? _InputMode.normal : _InputMode.osc;
    }
  }

  void _feedNormal(int codeUnit) {
    if (codeUnit == 0x1b) {
      _mode = _InputMode.afterEsc;
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
      _mode = _InputMode.csi;
      return;
    }
    if (codeUnit == 0x4f) {
      _mode = _InputMode.ss3;
      return;
    }
    if (codeUnit == 0x5d) {
      _mode = _InputMode.osc;
      return;
    }
    if (_isCsiFinal(codeUnit)) {
      _mode = _InputMode.normal;
      return;
    }
    _mode = _InputMode.normal;
  }

  void _feedOsc(int codeUnit) {
    if (codeUnit == 0x07) {
      _mode = _InputMode.normal;
      return;
    }
    if (codeUnit == 0x1b) {
      _mode = _InputMode.oscEsc;
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
    if (_completed) return;
    final line = _sanitizeCapturedLine(_buffer.toString());
    _buffer.clear();
    if (line.isEmpty) return;
    _completed = true;
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

enum _InputMode { normal, afterEsc, csi, ss3, osc, oscEsc }
