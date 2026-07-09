import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

enum HubPublishKind { team, expert }

class HubPublishRecord {
  const HubPublishRecord({
    required this.kind,
    required this.registryFullName,
    required this.slug,
    required this.prUrl,
    required this.publishedAtMs,
  });

  final HubPublishKind kind;
  final String registryFullName;
  final String slug;
  final String prUrl;
  final int publishedAtMs;

  String get _key => '${kind.name}:$slug';

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'registryFullName': registryFullName,
    'slug': slug,
    'prUrl': prUrl,
    'publishedAtMs': publishedAtMs,
  };

  static HubPublishRecord? fromJson(Map<String, Object?> json) {
    final kindName = json['kind']?.toString();
    HubPublishKind? kind;
    for (final value in HubPublishKind.values) {
      if (value.name == kindName) {
        kind = value;
        break;
      }
    }
    final registryFullName = json['registryFullName']?.toString();
    final slug = json['slug']?.toString();
    final prUrl = json['prUrl']?.toString();
    final publishedAtMs = json['publishedAtMs'];
    if (kind == null ||
        registryFullName == null ||
        registryFullName.isEmpty ||
        slug == null ||
        slug.isEmpty ||
        prUrl == null ||
        prUrl.isEmpty ||
        publishedAtMs is! num) {
      return null;
    }
    return HubPublishRecord(
      kind: kind,
      registryFullName: registryFullName,
      slug: slug,
      prUrl: prUrl,
      publishedAtMs: publishedAtMs.toInt(),
    );
  }
}

/// Local publish badges / history at `hub-publish/records.json`.
class HubPublishRecordStore {
  HubPublishRecordStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;
  final Map<String, HubPublishRecord> _records = {};

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.hubPublishRecordsJson;

  HubPublishRecord? find({
    required HubPublishKind kind,
    required String slug,
  }) => _records['${kind.name}:$slug'];

  Future<void> upsert(HubPublishRecord record) async {
    await _loadIfNeeded();
    _records[record._key] = record;
    await _save();
  }

  bool _loaded = false;

  Future<void> _loadIfNeeded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return;
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final items = root['records'];
      if (items is! List) return;
      for (final item in items) {
        if (item is! Map) continue;
        final record = HubPublishRecord.fromJson(item.cast<String, Object?>());
        if (record != null) {
          _records[record._key] = record;
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    final payload = {
      'records': _records.values.map((record) => record.toJson()).toList(),
    };
    await _fs.atomicWrite(_path, jsonEncode(payload));
  }
}
