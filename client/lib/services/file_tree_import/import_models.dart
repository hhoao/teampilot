import '../io/filesystem.dart';

enum ImportMode { copy, move }

class ImportSource {
  const ImportSource({required this.path, required this.isDirectory});

  final String path;
  final bool isDirectory;
}

class ImportPlan {
  const ImportPlan({
    required this.sources,
    required this.destDir,
    required this.mode,
    required this.sourceFs,
    required this.destFs,
    required this.flattenedFileCount,
    required this.maxFileBytes,
    required this.destIsLocal,
  });

  final List<ImportSource> sources;
  final String destDir;
  final ImportMode mode;
  final Filesystem sourceFs;
  final Filesystem destFs;
  final int flattenedFileCount;
  final int maxFileBytes;
  final bool destIsLocal;
}

enum ConflictChoice { overwrite, skip, cancelAll }

class ImportProgress {
  const ImportProgress({
    required this.completedItems,
    required this.totalItems,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.currentName = '',
  });

  final int completedItems;
  final int totalItems;
  final int bytesDone;
  final int bytesTotal;
  final String currentName;
}

class ImportSummary {
  const ImportSummary({
    this.succeeded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.cancelled = false,
    this.failedPaths = const [],
  });

  final int succeeded;
  final int skipped;
  final int failed;
  final bool cancelled;
  final List<String> failedPaths;
}
