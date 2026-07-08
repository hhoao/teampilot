import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../team_bus/bus_user_line_capture.dart';
import 'pending_user_message.dart';
import 'terminal_color_scheme_report.dart';
import '../../utils/every_user_line_capture.dart';
import '../../utils/first_user_line_capture.dart';

/// Engine→PTY byte path: user-line capture, bus intercept, OSC 997 stripping.
///
/// SRP: isolates input-side effects from session lifecycle and display I/O.
final class TerminalUserInputPipeline {
  TerminalUserInputPipeline({
    StreamController<PendingUserMessage>? parkedSubmissions,
  }) : _parkedSubmissions =
           parkedSubmissions ??
           StreamController<PendingUserMessage>.broadcast();

  final StreamController<PendingUserMessage> _parkedSubmissions;

  Stream<PendingUserMessage> get parkedUserSubmissions =>
      _parkedSubmissions.stream;

  FirstUserLineCapture? _firstUserLineCapture;
  EveryUserLineCapture? _everyUserLineCapture;
  EveryUserLineCapture? _turnStartCapture;
  BusUserLineCapture? _busUserLineCapture;
  BusUserInputRouting? _busRouting;
  var _forwardsColorScheme = true;

  void install({
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    void Function()? onTurnStart,
    BusUserInputRouting? busUserInputRouting,
    bool forwardsColorScheme = true,
  }) {
    _forwardsColorScheme = forwardsColorScheme;
    _firstUserLineCapture = onFirstUserLineSubmitted == null
        ? null
        : FirstUserLineCapture(onFirstUserLineSubmitted);
    _everyUserLineCapture = onEveryUserLineSubmitted == null
        ? null
        : EveryUserLineCapture(onEveryUserLineSubmitted);
    _turnStartCapture = onTurnStart == null
        ? null
        : EveryUserLineCapture((_) => onTurnStart());
    final incomingRouting = busUserInputRouting;
    _busRouting = incomingRouting;
    _busUserLineCapture = incomingRouting == null
        ? null
        : BusUserLineCapture(
            BusUserInputRouting(
              shouldIntercept: incomingRouting.shouldIntercept,
              isUnread: incomingRouting.isUnread,
              onTurnStart: incomingRouting.onTurnStart,
              onUserLine: (line) {
                final id = incomingRouting.onUserLine(line);
                if (id.isNotEmpty) {
                  _parkedSubmissions.add(
                    PendingUserMessage(id: id, content: line),
                  );
                }
                return id;
              },
            ),
          );
  }

  void installWorkspaceShell() {
    _forwardsColorScheme = true;
    _firstUserLineCapture = null;
    _everyUserLineCapture = null;
    _turnStartCapture = null;
    _busUserLineCapture = null;
    _busRouting = null;
  }

  void clear() {
    _firstUserLineCapture = null;
    _everyUserLineCapture = null;
    _turnStartCapture = null;
    _busUserLineCapture = null;
    _busRouting = null;
  }

  bool isUnreadParkedMessage(String id) =>
      _busRouting?.isUnread?.call(id) ?? false;

  /// Transform engine output before forwarding to the PTY (capture + filter).
  Uint8List transformEngineToPty(Uint8List data) {
    if (_firstUserLineCapture != null ||
        _everyUserLineCapture != null ||
        _turnStartCapture != null) {
      final decoded = utf8.decode(data, allowMalformed: true);
      _firstUserLineCapture?.feed(decoded);
      _everyUserLineCapture?.feed(decoded);
      _turnStartCapture?.feed(decoded);
    }
    var forward = _busUserLineCapture?.filter(data) ?? data;
    if (!_forwardsColorScheme) {
      forward = stripColorSchemeReport(forward);
    }
    return forward;
  }

  Future<void> close() => _parkedSubmissions.close();
}
