import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../io/filesystem.dart';
import 'remote_download_catalog.dart';
import 'remote_download_source.dart';

@immutable
class RemoteDownloadSettings {
  const RemoteDownloadSettings({
    this.sources = const [],
    this.mirrorBaseUrl,
  });

  factory RemoteDownloadSettings.fromJson(Map<String, Object?> json) {
    final rawSources = json['sources'] as List<Object?>?;
    return RemoteDownloadSettings(
      sources: rawSources
              ?.map(
                (entry) => RemoteDownloadSource.fromJson(
                  entry as Map<String, Object?>,
                ),
              )
              .toList() ??
          const [],
      mirrorBaseUrl: json['mirrorBaseUrl'] as String?,
    );
  }

  final List<RemoteDownloadSource> sources;
  final String? mirrorBaseUrl;

  Map<String, Object?> toJson() {
    return {
      if (sources.isNotEmpty)
        'sources': sources.map((s) => s.toJson()).toList(),
      if (mirrorBaseUrl != null) 'mirrorBaseUrl': mirrorBaseUrl,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RemoteDownloadSettings &&
            listEquals(sources, other.sources) &&
            mirrorBaseUrl == other.mirrorBaseUrl;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(sources), mirrorBaseUrl);
}

class RemoteDownloadSettingsStore {
  RemoteDownloadSettingsStore({required this.rootDir, required Filesystem fs})
      : _fs = fs;

  static const githubMirrorId = 'github-mirror';

  final String rootDir;
  final Filesystem _fs;

  String get _configDir =>
      _fs.pathContext.join(rootDir, '.remote-download');

  String get _configFile =>
      _fs.pathContext.join(_configDir, 'catalog.json');

  Future<RemoteDownloadSettings?> load() async {
    if (!(await _fs.stat(_configFile)).isFile) return null;
    try {
      final raw = await _fs.readString(_configFile);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      return RemoteDownloadSettings.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> save(RemoteDownloadSettings settings) async {
    await _fs.ensureDir(_configDir);
    await _fs.atomicWrite(_configFile, jsonEncode(settings.toJson()));
  }

  Future<void> clear() async {
    if ((await _fs.stat(_configFile)).exists) {
      await _fs.removeRecursive(_configFile);
    }
  }

  Future<RemoteDownloadCatalog> loadEffectiveCatalog() async {
    final settings = await load();
    if (settings == null) {
      return RemoteDownloadCatalog.defaults();
    }
    return _effectiveCatalogFromSettings(settings);
  }

  RemoteDownloadCatalog _effectiveCatalogFromSettings(
    RemoteDownloadSettings settings,
  ) {
    final defaults = RemoteDownloadCatalog.defaults();
    final defaultIds = defaults.sources.map((s) => s.id).toSet();

    var catalog = defaults.mergeOverrides(settings.sources);

    final mergedIds = catalog.sources.map((s) => s.id).toSet();
    final extraSources = settings.sources
        .where((s) => !defaultIds.contains(s.id) && !mergedIds.contains(s.id))
        .toList();
    if (extraSources.isNotEmpty) {
      catalog = RemoteDownloadCatalog([
        ...catalog.sources,
        ...extraSources,
      ]);
    }

    final mirrorBaseUrl = settings.mirrorBaseUrl?.trim();
    if (mirrorBaseUrl != null && mirrorBaseUrl.isNotEmpty) {
      final hasMirror = catalog.sources.any((s) => s.id == githubMirrorId);
      if (!hasMirror) {
        catalog = RemoteDownloadCatalog([
          ...catalog.sources,
          RemoteDownloadSource(
            id: githubMirrorId,
            priority: 20,
            enabled: true,
            matchHosts: const ['github.com', 'api.github.com'],
            rewriteOrigin: _trimTrailingSlash(mirrorBaseUrl),
          ),
        ]);
      }
    }

    return catalog;
  }

  static String _trimTrailingSlash(String url) {
    var trimmed = url.trimRight();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
