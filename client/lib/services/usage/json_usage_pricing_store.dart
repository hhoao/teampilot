import 'dart:convert';

import '../../models/session_usage_pricing.dart';
import '../io/filesystem.dart';
import 'usage_pricing_store.dart';

final class JsonUsagePricingStore implements UsagePricingStore {
  JsonUsagePricingStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;

  @override
  Future<UsagePricingLoad> load() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) {
      return const UsagePricingLoad(rules: []);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const UsagePricingLoad(rules: [], corrupted: true);
      }
      final rulesRaw = decoded['rules'];
      if (rulesRaw is! List) {
        return const UsagePricingLoad(rules: [], corrupted: true);
      }
      final rules = <UsagePriceRule>[];
      for (final entry in rulesRaw) {
        if (entry is! Map) continue;
        final rule = UsagePriceRule.fromJson(Map<String, Object?>.from(entry));
        if (rule.normalizedModel.isEmpty) continue;
        rules.add(rule);
      }
      return UsagePricingLoad(rules: List.unmodifiable(rules));
    } on Object {
      return const UsagePricingLoad(rules: [], corrupted: true);
    }
  }

  @override
  Future<void> save(List<UsagePriceRule> rules) {
    final payload = {
      'version': 1,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'rules': [
        for (final rule in rules)
          if (rule.normalizedModel.isNotEmpty) rule.toJson(),
      ],
    };
    return _fs.atomicWrite(
      _path,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}
