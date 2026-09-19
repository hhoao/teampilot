import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import 'compose_image_attachment.dart';

/// Clipboard image payload for landing compose import.
class ComposeImageClipboardPayload {
  const ComposeImageClipboardPayload({
    required this.bytes,
    required this.extension,
  });

  final List<int> bytes;
  final String extension;
}

/// Reads image data or image file paths from the system clipboard.
abstract interface class ComposeImageClipboardReader {
  Future<ComposeImageClipboardPayload?> readImageBytes();

  Future<List<String>> readImageFilePaths();
}

/// Desktop/mobile clipboard reader backed by [Pasteboard].
class PasteboardComposeImageClipboardReader
    implements ComposeImageClipboardReader {
  const PasteboardComposeImageClipboardReader();

  static bool get supported =>
      !kIsWeb &&
      (Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isAndroid);

  @override
  Future<ComposeImageClipboardPayload?> readImageBytes() async {
    if (!supported) return null;
    final bytes = await Pasteboard.image;
    if (bytes == null || bytes.isEmpty) return null;
    return ComposeImageClipboardPayload(
      bytes: Uint8List.fromList(bytes),
      extension: 'png',
    );
  }

  @override
  Future<List<String>> readImageFilePaths() async {
    if (!supported) return const [];
    final paths = await Pasteboard.files();
    final text = await Pasteboard.text;
    return parseClipboardImageFilePaths(filePaths: paths, clipboardText: text);
  }
}

/// Resolves image file paths from pasteboard file URIs and GNOME clipboard text.
List<String> parseClipboardImageFilePaths({
  required List<String> filePaths,
  required String? clipboardText,
}) {
  final resolved = <String>[];
  final seen = <String>{};

  void addPath(String raw) {
    final path = _normalizeClipboardPath(raw);
    if (path.isEmpty || !isComposeImagePath(path)) return;
    if (seen.add(path)) resolved.add(path);
  }

  for (final path in filePaths) {
    addPath(path);
  }

  final text = clipboardText?.trim();
  if (text == null || text.isEmpty) return resolved;

  final lines = text.split('\n');
  final start =
      lines.isNotEmpty && (lines.first == 'copy' || lines.first == 'cut')
      ? 1
      : 0;
  for (var i = start; i < lines.length; i++) {
    addPath(lines[i]);
  }

  return resolved;
}

String _normalizeClipboardPath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('file://')) {
    try {
      final uri = Uri.parse(trimmed);
      final looksLikeWindowsFileUri = RegExp(
        r'^/[A-Za-z]:/',
      ).hasMatch(uri.path);
      return uri.toFilePath(
        windows: Platform.isWindows && looksLikeWindowsFileUri,
      );
    } on Object {
      return trimmed.substring('file://'.length);
    }
  }
  return trimmed;
}
