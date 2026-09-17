import 'dart:isolate';
import 'dart:typed_data';

import 'package:ai_message_core/ai_message_core.dart';

final class HistoryTransferBundle {
  HistoryTransferBundle._({
    required this.adapterId,
    required this.fragments,
    required this.hints,
  });

  factory HistoryTransferBundle.fromBundle(AiTranscriptBundle bundle) {
    return HistoryTransferBundle._(
      adapterId: bundle.adapterId,
      fragments: [
        for (final fragment in bundle.fragments)
          HistoryTransferFragment(
            name: fragment.name,
            bytes: TransferableTypedData.fromList([
              Uint8List.fromList(fragment.bytes),
            ]),
          ),
      ],
      hints: Map<String, String>.of(bundle.hints),
    );
  }

  final String adapterId;
  final List<HistoryTransferFragment> fragments;
  final Map<String, String> hints;

  AiTranscriptBundle materialize() => AiTranscriptBundle(
    adapterId: adapterId,
    hints: hints,
    fragments: [for (final fragment in fragments) fragment.materialize()],
  );
}

final class HistoryTransferFragment {
  const HistoryTransferFragment({required this.name, required this.bytes});

  final String name;
  final TransferableTypedData bytes;

  AiTranscriptFragment materialize() => AiTranscriptFragment(
    name: name,
    bytes: bytes.materialize().asUint8List(),
  );
}
