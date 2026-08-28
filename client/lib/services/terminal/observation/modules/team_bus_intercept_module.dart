import 'dart:async';
import 'dart:typed_data';

import '../../../cli/registry/capabilities/terminal_observation_contributor.dart';
import '../../../team_bus/bus_user_line_capture.dart';
import '../../pending_user_message.dart';
import '../terminal_observation_bus.dart';
import '../terminal_observation_events.dart';
import '../terminal_observation_seat.dart';

/// Parks mixed-bus user submits via [BusUserLineCapture] at transform order 100.
final class TeamBusInterceptModule implements TerminalObservationContributor {
  TeamBusInterceptModule({
    required BusUserInputRouting routing,
    StreamController<PendingUserMessage>? parkedSubmissions,
  }) : _routing = routing,
       _parkedSubmissions =
           parkedSubmissions ??
           StreamController<PendingUserMessage>.broadcast();

  final BusUserInputRouting _routing;
  final StreamController<PendingUserMessage> _parkedSubmissions;

  Stream<PendingUserMessage> get parkedUserSubmissions =>
      _parkedSubmissions.stream;

  bool isUnreadParkedMessage(String id) => _routing.isUnread?.call(id) ?? false;

  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: _routing.shouldIntercept,
        isUnread: _routing.isUnread,
        onTurnStart: _routing.onTurnStart,
        onUserLine: (line) {
          final id = _routing.onUserLine(line);
          if (id.isNotEmpty) {
            _parkedSubmissions.add(PendingUserMessage(id: id, content: line));
          }
          return id;
        },
      ),
    );
    final subscription = bus.addInputTransform(_TeamBusInputTransform(capture));
    return CallbackObservationBinding(subscription.cancel);
  }

  Future<void> close() => _parkedSubmissions.close();
}

final class _TeamBusInputTransform implements TerminalInputTransform {
  _TeamBusInputTransform(this._capture);

  final BusUserLineCapture _capture;

  @override
  int get order => 100;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) {
    return _capture.filter(bytes);
  }
}
