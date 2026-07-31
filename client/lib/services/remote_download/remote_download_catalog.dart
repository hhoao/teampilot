import 'package:flutter/foundation.dart';

import 'remote_download_source.dart';

@immutable
class RemoteDownloadCatalog {
  const RemoteDownloadCatalog(this.sources);

  factory RemoteDownloadCatalog.defaults() => RemoteDownloadCatalog([
        const RemoteDownloadSource(
          id: 'github-official',
          priority: 10,
          enabled: true,
          matchHosts: ['github.com', 'api.github.com'],
          rewriteOrigin: null,
        ),
      ]);

  final List<RemoteDownloadSource> sources;

  RemoteDownloadCatalog mergeOverrides(List<RemoteDownloadSource> overrides) {
    final overrideById = {for (final o in overrides) o.id: o};
    return RemoteDownloadCatalog([
      for (final source in sources)
        overrideById[source.id] ?? source,
    ]);
  }

  List<RemoteDownloadSource> enabledSorted() =>
      sources.where((s) => s.enabled).toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RemoteDownloadCatalog && listEquals(sources, other.sources);
  }

  @override
  int get hashCode => Object.hashAll(sources);
}
