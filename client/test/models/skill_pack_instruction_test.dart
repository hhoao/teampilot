import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_pack_instruction.dart';

void main() {
  test('parses gstack-shaped install', () {
    final list = parseSkillPackInstall([
      {'FROM': 'garrytan/gstack@main'},
      {'SKILLS': '*'},
      {'RUN': './setup', 'optional': true},
      {'PATH': 'bin'},
    ]);
    expect(list, hasLength(4));
    expect(list[0], isA<FromInstruction>());
    final from = list[0] as FromInstruction;
    expect(from.owner, 'garrytan');
    expect(from.name, 'gstack');
    expect(from.branch, 'main');
    expect((list[1] as SkillsInstruction).includeAll, isTrue);
    expect((list[2] as RunInstruction).optional, isTrue);
    expect((list[3] as PathInstruction).entries, ['bin']);
  });

  test('SKILLS object include/exclude', () {
    final s = parseSkillPackInstall([
      {
        'SKILLS': {
          'include': ['*'],
          'exclude': ['qa'],
        },
      },
    ]).single as SkillsInstruction;
    expect(s.includeAll, isTrue);
    expect(s.exclude, ['qa']);
  });

  test('SKILLS list wildcard means include all', () {
    final s = parseSkillPackInstall([
      {'SKILLS': ['*']},
    ]).single as SkillsInstruction;
    expect(s.includeAll, isTrue);
    expect(s.include, isEmpty);
  });

  test('rejects dual keys and unknown keys', () {
    expect(
      () => parseSkillPackInstall([
        {'FROM': 'a/b', 'RUN': 'x'},
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseSkillPackInstall([
        {'LINK': 'bin'},
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('FROM defaults branch to main', () {
    final from =
        parseSkillPackInstall([
              {'FROM': 'owner/repo'},
            ]).single
            as FromInstruction;
    expect(from.branch, 'main');
  });

  group('resolveUnderRoot', () {
    test('joins relative path under root', () {
      expect(
        resolveUnderRoot(root: 'sync', relative: 'bin/foo'),
        'sync/bin/foo',
      );
    });

    test('accepts simple relative segment', () {
      expect(resolveUnderRoot(root: 'sync', relative: 'bin'), 'sync/bin');
    });

    test('normalizes backslashes', () {
      expect(
        resolveUnderRoot(root: 'sync', relative: r'bin\foo'),
        'sync/bin/foo',
      );
    });

    test('rejects absolute path', () {
      expect(
        () => resolveUnderRoot(root: 'sync', relative: '/abs/path'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects parent escape', () {
      expect(
        () => resolveUnderRoot(root: 'sync', relative: '../escape'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty relative path', () {
      expect(
        () => resolveUnderRoot(root: 'sync', relative: ''),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('SCRIPT object rejects unknown keys', () {
    expect(
      () => parseSkillPackInstall([
        {
          'SCRIPT': {
            'url': 'https://example.com/install.sh',
            'foo': 'bar',
          },
        },
      ]),
      throwsA(isA<FormatException>()),
    );
  });
}
