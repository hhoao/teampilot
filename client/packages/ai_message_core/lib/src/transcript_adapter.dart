import 'message.dart';

class AiTranscriptFragment {
  const AiTranscriptFragment({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

class AiTranscriptBundle {
  const AiTranscriptBundle({
    required this.adapterId,
    required this.fragments,
    this.hints = const {},
  });

  final String adapterId;
  final List<AiTranscriptFragment> fragments;
  final Map<String, String> hints;
}

abstract class AiTranscriptAdapter {
  String get id;

  Future<List<AiMessage>> parse(AiTranscriptBundle bundle);
}
