import 'dart:convert';
import 'dart:typed_data';

/// mixed bus：成员 park 在 [wait_for_message] 时，把用户在终端敲的一行交给 bus 而非 PTY。
class BusUserInputRouting {
  const BusUserInputRouting({
    required this.shouldIntercept,
    required this.onUserLine,
    this.isUnread,
    this.onTurnStart,
  });

  final bool Function() shouldIntercept;

  /// Submits captured input (may contain embedded newlines after a paste).
  /// Returns the delivered message id (empty if none), so the terminal session
  /// can track it for the parked-send overlay.
  final String Function(String line) onUserLine;

  /// Whether a previously-delivered message id is still unread in the target
  /// member's inbox. Null when not wired (overlay disabled).
  final bool Function(String id)? isUnread;

  /// Fired when the user submits a line while **not** parked — i.e. a turn the
  /// user starts directly at the member's own prompt (the lead's main path).
  /// Lets presence mark working off this positive edge instead of guessing from
  /// spinner-polluted PTY bytes. Null when not wired (non-mixed).
  final void Function()? onTurnStart;
}

/// 从 engine→PTY 字节流里解析「提交内容」。
///
/// park 期间**不**吞掉按键：照常透传给 CLI，由 CLI 自己的输入框就地回显；只把
/// 「回车提交」截下来——把缓冲投给 bus（`onUserLine`），并用 `Ctrl-U`（kill-line）
/// 清掉 CLI 输入框，避免 CLI 自己再当成一次提交处理。
///
/// **粘贴语义（与 bracketed paste 一致）：**
/// - `ESC[200~`…`ESC[201~` 内的换行是内容，不提交、不换 Ctrl-U；结束后按 Enter 才整段入队。
/// - 无 bracketed 时，单次 [filter] 调用内多行换行会合并成一次提交（兼容未开 paste 模式的 CLI）。
class BusUserLineCapture {
  BusUserLineCapture(this._routing);

  /// Ctrl-U：清空 CLI 当前输入行（readline / 多数 TUI 输入框通用）。
  static const int _killLine = 0x15;

  final BusUserInputRouting _routing;
  final StringBuffer _buffer = StringBuffer();
  final List<int> _pendingUtf8Bytes = [];
  final StringBuffer _csiParams = StringBuffer();
  _InputMode _mode = _InputMode.normal;
  var _inBracketedPaste = false;

  /// When >0, this [filter] call is a non-bracketed multi-line chunk: newlines
  /// are content until the last logical line ending, which submits once.
  var _coalesceRemaining = 0;

  /// After a CR, the following LF (CRLF) is not a second logical line ending.
  var _consumeLfAfterCr = false;

  /// 返回仍应写入 PTY 的字节。
  /// - parked(intercept): 原样透传,回车换成 Ctrl-U,内容投给 bus(`onUserLine`)。
  /// - 未 parked: 字节**完全不动**直透 PTY,只在解析出「非空提交」时触发
  ///   `onTurnStart`(回合开始 working 边)。
  Uint8List filter(Uint8List data) {
    final intercept = _routing.shouldIntercept();
    if (!intercept && _routing.onTurnStart == null) {
      _resetAll();
      return data; // 无 overlay 也无 turn-start 钩子:快路径。
    }
    final lineEnds = _countLogicalLineEnds(data);
    _coalesceRemaining =
        (!_inBracketedPaste && lineEnds > 1) ? lineEnds : 0;
    final out = BytesBuilder();
    for (final byte in data) {
      final emit = _feedCodeUnit(byte, intercept);
      if (intercept && emit != null) out.addByte(emit);
    }
    _coalesceRemaining = 0;
    // 未 parked:原字节一字不改透传,filter 仅作为 onTurnStart 的旁路探测。
    return intercept ? out.toBytes() : data;
  }

  /// 更新行缓冲 / 解析状态，返回应转发给 PTY 的字节（null = 吞掉，仅 intercept 用）。
  int? _feedCodeUnit(int codeUnit, bool intercept) {
    switch (_mode) {
      case _InputMode.normal:
        return _feedNormal(codeUnit, intercept);
      case _InputMode.afterEsc:
        _feedAfterEsc(codeUnit);
        return codeUnit;
      case _InputMode.csi:
        _feedCsi(codeUnit);
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

  int? _feedNormal(int codeUnit, bool intercept) {
    if (codeUnit == 0x1b) {
      _mode = _InputMode.afterEsc;
      _consumeLfAfterCr = false;
      return codeUnit; // 透传 ESC 序列起始
    }
    if (codeUnit == 0x0d || codeUnit == 0x0a) {
      return _feedLineEnding(codeUnit, intercept);
    }
    _consumeLfAfterCr = false;
    if (codeUnit == 0x7f || codeUnit == 0x08) {
      _backspace();
      return codeUnit; // 让 CLI 自己回退一格回显
    }
    if (codeUnit < 0x20 && codeUnit != 0x09) {
      return codeUnit; // 其他控制字节透传，不计入行缓冲
    }
    _appendUtf8Byte(codeUnit);
    return codeUnit; // 可见字符透传 → CLI 就地回显
  }

  int? _feedLineEnding(int codeUnit, bool intercept) {
    // CRLF: LF after CR is the same logical line ending.
    if (codeUnit == 0x0a && _consumeLfAfterCr) {
      _consumeLfAfterCr = false;
      if (_inBracketedPaste || _coalesceRemaining > 0) {
        // CR already wrote '\n' into the buffer (or will submit on final CR).
        return codeUnit;
      }
      // Bare LF after a submitting CR: empty submit, ignore.
      _submit(intercept);
      return intercept ? _killLine : codeUnit;
    }
    _consumeLfAfterCr = codeUnit == 0x0d;

    if (_inBracketedPaste) {
      _flushPendingUtf8();
      _buffer.write('\n');
      return codeUnit; // paste 内容：透传换行，不入队、不 Ctrl-U
    }

    if (_coalesceRemaining > 1) {
      _coalesceRemaining--;
      _flushPendingUtf8();
      _buffer.write('\n');
      return codeUnit; // 同 chunk 中间换行：并入缓冲
    }

    _coalesceRemaining = 0;
    _submit(intercept);
    // intercept:Ctrl-U 清掉 CLI 输入框;未 parked:原回车透传(返回值被忽略)。
    return intercept ? _killLine : codeUnit;
  }

  void _appendUtf8Byte(int byte) {
    _pendingUtf8Bytes.add(byte);
    try {
      _buffer.write(utf8.decode(_pendingUtf8Bytes));
      _pendingUtf8Bytes.clear();
    } on FormatException {
      // Incomplete UTF-8 sequence — wait for more bytes.
      if (_pendingUtf8Bytes.length >= 4) {
        _buffer.write('\uFFFD');
        _pendingUtf8Bytes.clear();
      }
    }
  }

  void _flushPendingUtf8() {
    if (_pendingUtf8Bytes.isEmpty) return;
    try {
      _buffer.write(utf8.decode(_pendingUtf8Bytes, allowMalformed: true));
    } finally {
      _pendingUtf8Bytes.clear();
    }
  }

  void _resetLineBuffer() {
    _buffer.clear();
    _pendingUtf8Bytes.clear();
  }

  void _resetAll() {
    _resetLineBuffer();
    _mode = _InputMode.normal;
    _inBracketedPaste = false;
    _csiParams.clear();
    _coalesceRemaining = 0;
    _consumeLfAfterCr = false;
  }

  void _feedAfterEsc(int codeUnit) {
    if (codeUnit == 0x5b) {
      _mode = _InputMode.csi;
      _csiParams.clear();
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

  void _feedCsi(int codeUnit) {
    if (_isCsiFinal(codeUnit)) {
      final params = _csiParams.toString();
      _csiParams.clear();
      if (codeUnit == 0x7e) {
        if (params == '200') {
          _inBracketedPaste = true;
          _coalesceRemaining = 0;
        } else if (params == '201') {
          _inBracketedPaste = false;
        }
      }
      _mode = _InputMode.normal;
      return;
    }
    // CSI parameter / intermediate bytes.
    if (codeUnit >= 0x30 && codeUnit <= 0x3f) {
      _csiParams.writeCharCode(codeUnit);
    }
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

  static bool _isCsiFinal(int codeUnit) => codeUnit >= 0x40 && codeUnit <= 0x7e;

  static int _countLogicalLineEnds(Uint8List data) {
    var count = 0;
    for (var i = 0; i < data.length; i++) {
      final b = data[i];
      if (b == 0x0d) {
        count++;
        if (i + 1 < data.length && data[i + 1] == 0x0a) i++;
      } else if (b == 0x0a) {
        count++;
      }
    }
    return count;
  }

  void _backspace() {
    if (_pendingUtf8Bytes.isNotEmpty) {
      _pendingUtf8Bytes.removeLast();
      return;
    }
    final text = _buffer.toString();
    if (text.isEmpty) return;
    _buffer
      ..clear()
      ..write(text.substring(0, text.length - 1));
  }

  void _submit(bool intercept) {
    _pendingUtf8Bytes.clear();
    final line = _sanitizeLine(_buffer.toString());
    _buffer.clear();
    if (line.isEmpty) return;
    if (intercept) {
      _routing.onUserLine(line); // parked:整段投给 bus 信箱。
    } else {
      _routing.onTurnStart?.call(); // 未 parked:仅标记回合开始,不取内容。
    }
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
