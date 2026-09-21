import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  const skill = Skill(
    id: 'local:demo',
    name: 'demo',
    description: 'd',
    directory: 'demo',
    installedAt: 1,
    updatedAt: 1,
  );

  late InMemoryFilesystem fs;
  late SkillRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs, appDataRoot: '/tp');
    repo = SkillRepository(storage: storage);
  });

  test('readSkillMarkdown returns SKILL.md text', () async {
    final dir = AppPaths.skillsDirForTeampilotRoot('/tp');
    final path = fs.pathContext.join(dir, 'demo', 'SKILL.md');
    await fs.writeString(path, '# Hello\n\nDo the thing.');

    expect(await repo.readSkillMarkdown(skill), '# Hello\n\nDo the thing.');
  });

  test('readSkillMarkdown returns null when SKILL.md is missing', () async {
    final dir = AppPaths.skillsDirForTeampilotRoot('/tp');
    await fs.ensureDir(fs.pathContext.join(dir, 'demo'));

    expect(await repo.readSkillMarkdown(skill), isNull);
  });
}
