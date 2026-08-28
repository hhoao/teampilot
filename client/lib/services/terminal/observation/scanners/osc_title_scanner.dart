import 'dart:convert';
import 'dart:typed_data';

import '../../../../utils/terminal/osc_title_extractor.dart';
import '../terminal_observation_events.dart';
import '../terminal_observation_seat.dart';

/// L1 OSC title scanner. Wraps [OscTitleExtractor]; installed on first
/// [OscTitle] subscriber.
final class OscTitleScanner implements TerminalOutputObserver {
  OscTitleScanner({required void Function(OscTitle event) emit}) : _emit = emit;

  final void Function(OscTitle event) _emit;
  final OscTitleExtractor _extractor = OscTitleExtractor();

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    if (bytes.isEmpty) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    for (final title in _extractor.push(text)) {
      _emit(OscTitle(title));
    }
  }

  void reset() => _extractor.reset();
}
