import 'dart:convert';
import 'dart:io';

import '../models/llm_config.dart';

class LlmConfigRepository {
  const LlmConfigRepository(this.file);

  final File file;

  Future<LlmConfig> load() async {
    if (!await file.exists()) {
      return const LlmConfig();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const LlmConfig();
      }
      return LlmConfig.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const LlmConfig();
    } on TypeError {
      return const LlmConfig();
    }
  }

  Future<void> save(LlmConfig config, {LlmConfig? previous}) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(config.toJson(previous: previous)),
    );
  }
}
