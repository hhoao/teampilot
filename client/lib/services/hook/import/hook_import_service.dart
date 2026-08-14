import '../hook_repository.dart';
import 'hook_import_parser.dart';

export 'hook_import_parser.dart';

/// 把导入 drafts 落库：save 定义 + writeScript 脚本（幂等 upsert）。
class HookImportService {
  HookImportService({required HookRepository repository})
    : _repository = repository;

  final HookRepository _repository;

  Future<int> import(List<HookImportDraft> drafts) async {
    var count = 0;
    for (final draft in drafts) {
      await _repository.save(draft.definition);
      final fileName = draft.scriptFileName;
      final content = draft.scriptContent;
      if (fileName != null && content != null && content.isNotEmpty) {
        await _repository.writeScript(draft.definition.id, fileName, content);
      }
      count++;
    }
    return count;
  }
}
