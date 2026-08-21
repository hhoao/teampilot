import 'import_models.dart';

/// Stable dedup identity for [ImportPlan] file-tree import jobs.
String importPlanHash(ImportPlan plan) => Object.hash(
  plan.destDir,
  plan.mode,
  plan.flattenedFileCount,
  plan.maxFileBytes,
  plan.destIsLocal,
  plan.sources.map((s) => '${s.path}:${s.isDirectory}').join('|'),
).toString();
