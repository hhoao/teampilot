import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:uuid/uuid.dart';

import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../storage/app_storage.dart';
import '../../utils/workspace_path_utils.dart';
import 'compose_image_attachment.dart';
import 'compose_image_clipboard.dart';
import 'compose_text_edit.dart';

bool _isWindowsStylePath(String path) =>
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path.trim());

/// Formats an absolute path as an `@` reference for compose input.
///
/// Paths under [workspaceRoot] are expressed relative to that root with forward
/// slashes; other paths keep their normalized spelling.
String formatComposeFileReference(
  String absolutePath, {
  required String workspaceRoot,
}) {
  final normalized = normalizeWorkspacePath(absolutePath);
  final root = normalizeWorkspacePath(workspaceRoot);
  if (root.isNotEmpty && _isUnderRoot(normalized, root)) {
    var rel = _stripRootPrefix(normalized, root);
    rel = rel.replaceAll(r'\', '/');
    return '@$rel';
  }
  return '@${normalized.replaceAll(r'\', '/')}';
}

String _pathKey(String path) {
  if (Platform.isWindows || _isWindowsStylePath(path)) {
    return path.toLowerCase();
  }
  return path;
}

String _separatorForPath(String path) {
  if (_isWindowsStylePath(path)) return r'\';
  return p.separator;
}

String _stripRootPrefix(String path, String root) {
  if (_pathKey(path) == _pathKey(root)) return '';
  final sep = _separatorForPath(path);
  final rootWithSep = root.endsWith('/') || root.endsWith(r'\')
      ? root
      : '$root$sep';
  if (_pathKey(path).startsWith(_pathKey(rootWithSep))) {
    return path.substring(rootWithSep.length);
  }
  var rel = path.substring(root.length);
  if (rel.startsWith('/') || rel.startsWith(r'\')) {
    rel = rel.substring(1);
  }
  return rel;
}

bool _isUnderRoot(String path, String root) {
  if (_pathKey(path) == _pathKey(root)) return true;
  final sep = _separatorForPath(path);
  final rootWithSep = root.endsWith('/') || root.endsWith(r'\')
      ? root
      : '$root$sep';
  return _pathKey(path).startsWith(_pathKey(rootWithSep));
}

/// Inserts `@` file references at the compose cursor.
void insertComposeReferences(
  TextEditingController controller,
  Iterable<String> references,
) {
  final refs = references.map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
  if (refs.isEmpty) return;
  controller.value = insertTextAtSelection(
    controller,
    '${refs.join(' ')} ',
    separatorBefore: ' ',
  );
}

Future<String?> resolveComposeFileReference({
  required String absolutePath,
  required String workspaceRoot,
  Filesystem? filesystem,
}) async {
  if (isComposeImagePath(absolutePath)) {
    return resolveComposeImageReference(
      absolutePath: absolutePath,
      workspaceRoot: workspaceRoot,
    );
  }
  return formatComposeFileReference(absolutePath, workspaceRoot: workspaceRoot);
}

/// Pastes a clipboard image (or copied image file) into compose as an `@` reference.
Future<bool> pasteComposeImageAttachment({
  required TextEditingController controller,
  required String workspaceRoot,
  ComposeImageClipboardReader? clipboardReader,
  ComposeImageIdGenerator? idGenerator,
  String? attachmentsDir,
  Future<String> Function()? resolveAttachmentsDir,
  Filesystem? importFilesystem,
}) async {
  final reader = clipboardReader ?? const PasteboardComposeImageClipboardReader();
  final generateId = idGenerator ?? _defaultComposeImageId;

  final payload = await reader.readImageBytes();
  if (payload != null) {
    final importDir = attachmentsDir ??
        await (resolveAttachmentsDir ??
            DefaultWorkspaceDirectory.resolveTeamPilotAttachmentsPath)();
    final writeFs = importFilesystem ?? LocalFilesystem();
    final ref = await importComposeImageBytes(
      bytes: payload.bytes,
      extension: payload.extension,
      attachmentsDir: importDir,
      workspaceRoot: workspaceRoot,
      filesystem: writeFs,
      idGenerator: generateId,
    );
    if (ref != null) {
      insertComposeReferences(controller, [ref]);
      return true;
    }
  }

  final refs = <String>[];
  for (final path in await reader.readImageFilePaths()) {
    if (!isComposeImagePath(path)) continue;
    final ref = await resolveComposeImageReference(
      absolutePath: path,
      workspaceRoot: workspaceRoot,
    );
    if (ref != null) refs.add(ref);
  }
  if (refs.isNotEmpty) {
    insertComposeReferences(controller, refs);
    return true;
  }

  return false;
}

/// Opens a multi-file picker and inserts `@` references at the compose cursor.
Future<void> pickAndInsertComposeFileReferences({
  required TextEditingController controller,
  required String workspaceRoot,
  Filesystem? filesystem,
}) async {
  final fs = filesystem ?? AppStorage.fs;
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.any,
  );
  if (result == null || result.files.isEmpty) return;

  final refs = <String>[];
  for (final file in result.files) {
    final path = file.path?.trim() ?? '';
    if (path.isEmpty) continue;
    final ref = await resolveComposeFileReference(
      absolutePath: path,
      workspaceRoot: workspaceRoot,
      filesystem: fs,
    );
    if (ref != null) refs.add(ref);
  }
  if (refs.isEmpty) return;

  insertComposeReferences(controller, refs);
}

const _composeImageUuid = Uuid();

String _defaultComposeImageId() => _composeImageUuid.v4();
