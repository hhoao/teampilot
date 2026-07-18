import 'package:ai_message_core/ai_message_core.dart';

String normalizeAiHistoryPendingText(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String aiHistoryUserPlainText(AiMessage m) =>
    m.parts.whereType<AiTextPart>().map((p) => p.text).join('\n');
