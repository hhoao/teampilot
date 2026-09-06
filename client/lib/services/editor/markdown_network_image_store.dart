import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../storage/app_storage.dart';
import '../../utils/async_keyed_coalescer.dart';

/// HTTP get that can attach conditional-request headers.
typedef MarkdownNetworkImageHttpGet = Future<http.Response?> Function(
  Uri uri, {
  Map<String, String>? headers,
});

/// Bytes + sniff result returned by [MarkdownNetworkImageStore.load].
final class MarkdownImagePayload {
  const MarkdownImagePayload({
    required this.bytes,
    required this.isSvg,
    this.etag,
    this.lastModified,
  });

  final Uint8List bytes;
  final bool isSvg;
  final String? etag;
  final String? lastModified;
}

/// Shared memory + disk cache and concurrency gate for markdown network images.
///
/// Badge rows fire many parallel requests; [maxConcurrent] caps in-flight HTTP.
/// Disk entries keep ETag / Last-Modified for conditional revalidation so
/// cold starts after process restart skip full downloads when unchanged.
class MarkdownNetworkImageStore {
  MarkdownNetworkImageStore({
    Directory? cacheDir,
    this.maxConcurrent = 4,
    this.revalidateOnLoad = false,
    MarkdownNetworkImageHttpGet? httpGet,
    int maxMemoryEntries = 64,
    int maxMemoryBytes = 32 * 1024 * 1024,
    int maxDiskEntries = 256,
  }) : _cacheDir = cacheDir,
       _httpGet = httpGet ?? _defaultHttpGet,
       _maxMemoryEntries = maxMemoryEntries,
       _maxMemoryBytes = maxMemoryBytes,
       _maxDiskEntries = maxDiskEntries;

  /// Process-wide store used by [MarkdownNetworkImage] in production.
  static MarkdownNetworkImageStore get instance =>
      _instance ??= MarkdownNetworkImageStore(cacheDir: _defaultCacheDir());
  static MarkdownNetworkImageStore? _instance;

  static Directory? _defaultCacheDir() {
    if (!AppStorage.isInstalled) return null;
    try {
      return Directory(
        p.join(AppStorage.paths.basePath, 'cache', 'markdown-images'),
      );
    } on Object catch (_) {
      return null;
    }
  }

  final Directory? _cacheDir;
  final MarkdownNetworkImageHttpGet _httpGet;
  final int maxConcurrent;
  /// When true, disk hits still issue a conditional GET (tests / freshness).
  final bool revalidateOnLoad;
  final int _maxMemoryEntries;
  final int _maxMemoryBytes;
  final int _maxDiskEntries;

  final LinkedHashMap<String, MarkdownImagePayload> _memory = LinkedHashMap();
  final AsyncKeyedCoalescer _coalescer = AsyncKeyedCoalescer();
  final _Gate _gate = _Gate();
  static const _fetchTimeout = Duration(seconds: 30);

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }

  @visibleForTesting
  static void resetMemoryForTest() {
    _instance?._memory.clear();
  }

  /// Clears only this instance's memory cache (disk untouched).
  void clearMemory() => _memory.clear();

  Future<MarkdownImagePayload?> load(String url) {
    final cached = _memoryLookup(url);
    if (cached != null && !revalidateOnLoad) return Future.value(cached);
    return _coalescer.run(url, () => _gate.run(maxConcurrent, () => _loadBody(url)));
  }

  /// Warm cache for [urls] without awaiting each consumer.
  Future<void> prefetch(Iterable<String> urls) async {
    final unique = <String>{
      for (final u in urls)
        if (u.trim().isNotEmpty) u.trim(),
    };
    await Future.wait(unique.map(load));
  }

  Future<MarkdownImagePayload?> _loadBody(String url) async {
    if (!revalidateOnLoad) {
      final mem = _memoryLookup(url);
      if (mem != null) return mem;
    }

    final disk = await _diskRead(url);
    if (disk != null && !revalidateOnLoad) {
      _memoryStore(url, disk);
      return disk;
    }

    return _fetchAndStore(url, prior: disk);
  }

  Future<MarkdownImagePayload?> _fetchAndStore(
    String url, {
    MarkdownImagePayload? prior,
  }) async {
    final headers = <String, String>{};
    if (prior?.etag != null && prior!.etag!.isNotEmpty) {
      headers['if-none-match'] = prior.etag!;
    } else if (prior?.lastModified != null && prior!.lastModified!.isNotEmpty) {
      headers['if-modified-since'] = prior.lastModified!;
    }

    http.Response? response;
    try {
      response = await _httpGet(Uri.parse(url), headers: headers.isEmpty ? null : headers);
    } on Exception catch (_) {
      response = null;
    } on Error catch (_) {
      response = null;
    }

    if (response == null) {
      if (prior != null) {
        _memoryStore(url, prior);
        return prior;
      }
      return null;
    }

    if (response.statusCode == 304 && prior != null) {
      _memoryStore(url, prior);
      return prior;
    }
    if (response.statusCode != 200) {
      if (prior != null) {
        _memoryStore(url, prior);
        return prior;
      }
      return null;
    }

    final bytes = response.bodyBytes;
    final etag = response.headers['etag'];
    final lastModified = response.headers['last-modified'];
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final isSvg = contentType.contains('svg') || _isSvgBytes(bytes);
    final payload = MarkdownImagePayload(
      bytes: bytes,
      isSvg: isSvg,
      etag: etag,
      lastModified: lastModified,
    );
    _memoryStore(url, payload);
    await _diskWrite(url, payload, contentType: contentType);
    return payload;
  }

  MarkdownImagePayload? _memoryLookup(String url) {
    final hit = _memory.remove(url);
    if (hit != null) _memory[url] = hit;
    return hit;
  }

  void _memoryStore(String url, MarkdownImagePayload payload) {
    _memory
      ..remove(url)
      ..[url] = payload;
    var total = 0;
    for (final value in _memory.values) {
      total += value.bytes.lengthInBytes;
    }
    while (_memory.isNotEmpty &&
        (_memory.length > _maxMemoryEntries || total > _maxMemoryBytes)) {
      total -= _memory.values.first.bytes.lengthInBytes;
      _memory.remove(_memory.keys.first);
    }
  }

  Directory get _resolvedCacheDir {
    final injected = _cacheDir;
    if (injected != null) return injected;
    return Directory(
      p.join(Directory.systemTemp.path, 'teampilot-markdown-images'),
    );
  }

  String _key(String url) => sha256.convert(utf8.encode(url)).toString();

  Future<MarkdownImagePayload?> _diskRead(String url) async {
    try {
      final dir = _resolvedCacheDir;
      final key = _key(url);
      final metaFile = File(p.join(dir.path, '$key.json'));
      final binFile = File(p.join(dir.path, '$key.bin'));
      if (!await metaFile.exists() || !await binFile.exists()) return null;
      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final bytes = await binFile.readAsBytes();
      return MarkdownImagePayload(
        bytes: bytes,
        isSvg: meta['isSvg'] == true || _isSvgBytes(bytes),
        etag: meta['etag'] as String?,
        lastModified: meta['lastModified'] as String?,
      );
    } on Exception catch (_) {
      return null;
    } on Error catch (_) {
      return null;
    }
  }

  Future<void> _diskWrite(
    String url,
    MarkdownImagePayload payload, {
    required String contentType,
  }) async {
    try {
      final dir = _resolvedCacheDir;
      await dir.create(recursive: true);
      final key = _key(url);
      final metaFile = File(p.join(dir.path, '$key.json'));
      final binFile = File(p.join(dir.path, '$key.bin'));
      await binFile.writeAsBytes(payload.bytes, flush: true);
      await metaFile.writeAsString(
        jsonEncode({
          'url': url,
          'etag': payload.etag,
          'lastModified': payload.lastModified,
          'contentType': contentType,
          'isSvg': payload.isSvg,
          'savedAtMs': DateTime.now().millisecondsSinceEpoch,
        }),
        flush: true,
      );
      await _diskEvictIfNeeded(dir);
    } on Exception catch (_) {
      // Disk is best-effort.
    } on Error catch (_) {}
  }

  Future<void> _diskEvictIfNeeded(Directory dir) async {
    final metas = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        metas.add(entity);
      }
    }
    if (metas.length <= _maxDiskEntries) return;
    final dated = <({File meta, int savedAt})>[];
    for (final meta in metas) {
      try {
        final map =
            jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        dated.add((
          meta: meta,
          savedAt: (map['savedAtMs'] as int?) ?? 0,
        ));
      } on Exception catch (_) {
        dated.add((meta: meta, savedAt: 0));
      }
    }
    dated.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    final overflow = dated.length - _maxDiskEntries;
    for (var i = 0; i < overflow; i++) {
      final meta = dated[i].meta;
      final bin = File(meta.path.replaceAll(RegExp(r'\.json$'), '.bin'));
      try {
        await meta.delete();
      } on Exception catch (_) {}
      try {
        if (await bin.exists()) await bin.delete();
      } on Exception catch (_) {}
    }
  }

  static Future<http.Response?> _defaultHttpGet(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    try {
      return await http.get(uri, headers: headers).timeout(_fetchTimeout);
    } on Exception catch (_) {
      return null;
    }
  }
}

bool _isSvgBytes(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final head = String.fromCharCodes(bytes.skip(start).take(1024)).toLowerCase();
  return head.trimLeft().startsWith('<') && head.contains('<svg');
}

class _Gate {
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue();

  Future<T> run<T>(int maxConcurrent, Future<T> Function() work) async {
    while (_active >= maxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _active++;
    try {
      return await work();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
}
