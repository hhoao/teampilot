import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import '../../services/editor/markdown_network_image_store.dart';

/// Fetcher used by [MarkdownNetworkImage]; overridable in tests.
///
/// When set, bypasses [MarkdownNetworkImageStore] (no concurrency gate / disk).
typedef MarkdownNetworkImageFetch = Future<http.Response?> Function(Uri uri);

/// Network image that renders both SVG and raster payloads.
///
/// Markdown badges and remote screenshots may serve SVG from URLs with no
/// `.svg` extension. Flutter's raster decoders reject SVG bytes (`Invalid
/// image data`). This widget loads via [MarkdownNetworkImageStore] (memory +
/// disk LRU, concurrency gate, ETag), sniffs the payload, normalizes
/// shields-style SVG text scaling as a fallback, and renders [SvgPicture] or
/// [Image]. Callers should rewrite shields.io URLs to PNG first
/// ([preferRasterBadgeUrl]) so logos survive. Failures collapse to
/// [SizedBox.shrink].
class MarkdownNetworkImage extends StatefulWidget {
  const MarkdownNetworkImage({
    super.key,
    required this.url,
    this.fetch,
    this.store,
  });

  final String url;

  /// Test hook; when set, skips [store] / [MarkdownNetworkImageStore.instance].
  final MarkdownNetworkImageFetch? fetch;

  /// Override for tests; defaults to [MarkdownNetworkImageStore.instance].
  final MarkdownNetworkImageStore? store;

  @override
  State<MarkdownNetworkImage> createState() => _MarkdownNetworkImageState();
}

class _MarkdownNetworkImageState extends State<MarkdownNetworkImage> {
  Uint8List? _bytes;
  bool _svg = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MarkdownNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url &&
        oldWidget.fetch == widget.fetch &&
        oldWidget.store == widget.store) {
      return;
    }
    _bytes = null;
    _svg = false;
    _failed = false;
    _load();
  }

  Future<void> _load() async {
    final fetch = widget.fetch;
    if (fetch != null) {
      await _loadViaFetch(fetch);
      return;
    }

    final payload =
        await (widget.store ?? MarkdownNetworkImageStore.instance).load(
      widget.url,
    );
    if (!mounted) return;
    if (payload == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _bytes = payload.bytes;
      _svg = payload.isSvg;
      _failed = false;
    });
  }

  Future<void> _loadViaFetch(MarkdownNetworkImageFetch fetch) async {
    http.Response? response;
    try {
      response = await fetch(Uri.parse(widget.url));
    } on Exception catch (_) {
      response = null;
    } on Error catch (_) {
      response = null;
    }
    if (!mounted) return;
    if (response == null || response.statusCode != 200) {
      setState(() => _failed = true);
      return;
    }
    final bytes = response.bodyBytes;
    final svg =
        (response.headers['content-type']?.toLowerCase().contains('svg') ??
            false) ||
        _isSvgBytes(bytes);
    setState(() {
      _bytes = bytes;
      _svg = svg;
      _failed = false;
    });
  }

  /// SVG sources start with markup and contain an `<svg` root (rasters start
  /// with binary magic like `\x89PNG`).
  static bool _isSvgBytes(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final head = String.fromCharCodes(
      bytes.skip(start).take(1024),
    ).toLowerCase();
    return head.trimLeft().startsWith('<') && head.contains('<svg');
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (_failed || bytes == null) return const SizedBox.shrink();
    if (_svg) {
      final raw = utf8.decode(bytes, allowMalformed: true);
      return SvgPicture.string(
        normalizeShieldsBadgeSvg(raw),
        // scaleDown: under block-level loose constraints (bounded width,
        // unbounded height) `contain` would upscale a 108x20 badge to the
        // full column width. scaleDown keeps intrinsic size and only clamps
        // oversized art — matching the raster `Image` path.
        fit: BoxFit.scaleDown,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    return Image(
      image: MemoryImage(bytes),
      // scaleDown: do not upscale 1x badge PNGs to a larger line box.
      fit: BoxFit.scaleDown,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

/// Flatten shields.io's `font-size="110"` / `110px` + `transform="scale(.1)"`
/// text trick.
///
/// flutter_svg paints that text without applying the scale, so labels appear
/// as magnified clipped fragments. Dividing text geometry by 10 and dropping
/// the scale groups restores the intended 20px-tall badge appearance. Prefer
/// [preferRasterBadgeUrl] for shields.io when logos matter — nested
/// `<image href="data:…">` logos are still dropped by flutter_svg.
String normalizeShieldsBadgeSvg(String svg) {
  final hasScale = svg.contains('scale(.1)') || svg.contains('scale(0.1)');
  final has110 =
      svg.contains('font-size="110"') || svg.contains('font-size="110px"');
  if (!hasScale || !has110) return svg;

  var out = svg
      .replaceAll('font-size="110px"', 'font-size="11px"')
      .replaceAll('font-size="110"', 'font-size="11"');
  out = out.replaceAllMapped(
    RegExp(r'''stdDeviation="([\d.]+)"'''),
    (m) {
      final v = double.parse(m[1]!) / 10;
      return 'stdDeviation="${_svgNumber(v)}"';
    },
  );
  out = out.replaceAllMapped(RegExp(r'<text\b([^>]*)>'), (m) {
    var attrs = m[1]!;
    attrs = attrs.replaceAllMapped(
      RegExp(r'''\b(x|y|textLength)="([\d.]+)"'''),
      (a) {
        final v = double.parse(a[2]!) / 10;
        return '${a[1]}="${_svgNumber(v)}"';
      },
    );
    attrs = attrs.replaceAll(
      RegExp(r'''\s*transform="scale\(\.?0?\.?1\)"'''),
      '',
    );
    attrs = attrs.replaceAll(
      RegExp(r"""\s*transform='scale\(\.?0?\.?1\)'"""),
      '',
    );
    return '<text$attrs>';
  });
  out = out.replaceAll(RegExp(r'''\s*transform="scale\(\.?0?\.?1\)"'''), '');
  out = out.replaceAll(RegExp(r"""\s*transform='scale\(\.?0?\.?1\)'"""), '');
  return out;
}

String _svgNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var s = value.toStringAsFixed(4);
  while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}
