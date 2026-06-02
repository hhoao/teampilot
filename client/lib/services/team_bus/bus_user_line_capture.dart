import 'dart:typed_data';

/// mixed bus：成员 park 在 [wait_for_message] 时，把用户在终端敲的一行交给 bus 而非 PTY。
class BusUserInputRouting {
  const BusUserInputRouting({
    required this.shouldIntercept,
    required this.onUserLine,
  });

  final bool Function() shouldIntercept;
  final void Function(String line) onUserLine;
}

/// 从 engine→PTY 字节流里解析「一行」，在 intercept 期间吞掉全部 keystroke。
class BusUserLineCapture {
  BusUserLineCapture(this._routing);

  final BusUserInputRouting _routing;
  final StringBuffer _buffer = StringBuffer();
  _InputMode _mode = _InputMode.normal;

  /// 返回仍应写入 PTY 的字节（intercept 期间通常为空）。
  Uint8List filter(Uint8List data) {
    if (!_routing.shouldIntercept()) {
      _buffer.clear();
      _mode = _InputMode.normal;
      return data;
    }
    for (final byte in data) {
      _feedCodeUnit(byte);
    }
    return Uint8List(0);
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
    final line = _sanitizeLine(_buffer.toString());
    _buffer.clear();
    if (line.isEmpty) return;
    _routing.onUserLine(line);
  }

  static String _sanitizeLine(String raw) {
    return raw
        .replaceAll(RegExp(r'\x1b\[[\x30-\x3f\x20-\x2f]*[\x40-\x7e]'), '')
        .replaceAll(RegExp(r'\[[\x30-\x3f\x20-\x2f]*[\x40-\x7e]'), '')
        .replaceAll(RegExp(r'\x1b.'), '')
        .trim();
  }
}

enum _InputMode { normal, afterEsc, csi, ss3, osc, oscEsc }
