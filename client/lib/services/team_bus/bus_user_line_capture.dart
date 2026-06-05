import 'dart:typed_data';

/// mixed bus：成员 park 在 [wait_for_message] 时，把用户在终端敲的一行交给 bus 而非 PTY。
class BusUserInputRouting {
  const BusUserInputRouting({
    required this.shouldIntercept,
    required this.onUserLine,
    this.isUnread,
  });

  final bool Function() shouldIntercept;

  /// Submits a captured line. Returns the delivered message id (empty if none),
  /// so the terminal session can track it for the parked-send overlay.
  final String Function(String line) onUserLine;

  /// Whether a previously-delivered message id is still unread in the target
  /// member's inbox. Null when not wired (overlay disabled).
  final bool Function(String id)? isUnread;
}

/// 从 engine→PTY 字节流里解析「一行」。
///
/// park 期间**不**吞掉按键：照常透传给 CLI，由 CLI 自己的输入框就地回显；只把
/// 「回车提交」截下来——把这一行投给 bus（`onUserLine`），并用 `Ctrl-U`（kill-line）
/// 清掉 CLI 输入框里的同一行，避免 CLI 自己再当成一次提交处理。
class BusUserLineCapture {
  BusUserLineCapture(this._routing);

  /// Ctrl-U：清空 CLI 当前输入行（readline / 多数 TUI 输入框通用）。
  static const int _killLine = 0x15;

  final BusUserInputRouting _routing;
  final StringBuffer _buffer = StringBuffer();
  _InputMode _mode = _InputMode.normal;

  /// 返回仍应写入 PTY 的字节。park 期间 = 原样透传（回车换成 Ctrl-U）。
  Uint8List filter(Uint8List data) {
    if (!_routing.shouldIntercept()) {
      _buffer.clear();
      _mode = _InputMode.normal;
      return data;
    }
    final out = BytesBuilder();
    for (final byte in data) {
      final emit = _feedCodeUnit(byte);
      if (emit != null) out.addByte(emit);
    }
    return out.toBytes();
  }

  /// 更新行缓冲 / 解析状态，返回应转发给 PTY 的字节（null = 吞掉）。
  int? _feedCodeUnit(int codeUnit) {
    switch (_mode) {
      case _InputMode.normal:
        return _feedNormal(codeUnit);
      case _InputMode.afterEsc:
        _feedAfterEsc(codeUnit);
        return codeUnit;
      case _InputMode.csi:
        if (_isCsiFinal(codeUnit)) _mode = _InputMode.normal;
        return codeUnit;
      case _InputMode.ss3:
        _mode = _InputMode.normal;
        return codeUnit;
      case _InputMode.osc:
        _feedOsc(codeUnit);
        return codeUnit;
      case _InputMode.oscEsc:
        _mode = codeUnit == 0x5c ? _InputMode.normal : _InputMode.osc;
        return codeUnit;
    }
  }

  int? _feedNormal(int codeUnit) {
    if (codeUnit == 0x1b) {
      _mode = _InputMode.afterEsc;
      return codeUnit; // 透传 ESC 序列起始
    }
    if (codeUnit == 0x0d || codeUnit == 0x0a) {
      _submit();
      return _killLine; // 截下提交：行进 bus，Ctrl-U 清掉 CLI 输入框
    }
    if (codeUnit == 0x7f || codeUnit == 0x08) {
      _backspace();
      return codeUnit; // 让 CLI 自己回退一格回显
    }
    if (codeUnit < 0x20 && codeUnit != 0x09) {
      return codeUnit; // 其他控制字节透传，不计入行缓冲
    }
    _buffer.writeCharCode(codeUnit);
    return codeUnit; // 可见字符透传 → CLI 就地回显
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
