import 'download_candidate.dart';
import 'remote_download_catalog.dart';
import 'remote_download_source.dart';

class RemoteDownloadResolver {
  RemoteDownloadResolver(RemoteDownloadCatalog catalog)
      : _catalogProvider = _providerFor(catalog);

  RemoteDownloadResolver.withProvider(this._catalogProvider);

  final RemoteDownloadCatalog Function() _catalogProvider;

  static RemoteDownloadCatalog Function() _providerFor(
    RemoteDownloadCatalog catalog,
  ) {
    return () => catalog;
  }

  List<DownloadCandidate> resolve(Uri uri) {
    final sources = _catalogProvider().enabledSorted();
    final candidates = <DownloadCandidate>[];

    for (final source in sources) {
      if (_matches(uri, source)) {
        candidates.add(_toCandidate(uri, source));
      }
    }

    if (candidates.isEmpty) {
      return [DownloadCandidate(uri: uri, sourceId: 'passthrough')];
    }
    return candidates;
  }

  bool _matches(Uri uri, RemoteDownloadSource source) {
    final host = uri.host.toLowerCase();
    final matchesHost = source.matchHosts.any(
      (matchHost) => matchHost.toLowerCase() == host,
    );
    if (!matchesHost) {
      return false;
    }

    final prefix = source.matchPathPrefix;
    if (prefix != null && !uri.path.startsWith(prefix)) {
      return false;
    }

    return true;
  }

  DownloadCandidate _toCandidate(Uri uri, RemoteDownloadSource source) {
    final rewriteOrigin = source.rewriteOrigin;
    if (rewriteOrigin == null) {
      return DownloadCandidate(uri: uri, sourceId: source.id);
    }

    final origin = Uri.parse(rewriteOrigin);
    final rewritten = uri.replace(
      scheme: origin.scheme,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
    );
    return DownloadCandidate(uri: rewritten, sourceId: source.id);
  }
}
