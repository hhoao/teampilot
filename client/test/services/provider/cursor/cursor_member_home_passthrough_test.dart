import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_member_home_passthrough.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorHomeLayout layout;
  late CursorMemberHomePassthrough passthrough;

  const realHome = '/home/user';
  const memberHome = '/tp/workspace/ws/runtime/planner/cursor/home';

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    passthrough = CursorMemberHomePassthrough(fs: fs, layout: layout);
  });

  Future<void> seedRealHome() async {
    await fs.ensureDir(realHome);
    await fs.ensureDir(fs.pathContext.join(realHome, '.rustup', 'toolchains'));
    await fs.writeString(
      fs.pathContext.join(realHome, '.rustup', 'toolchains', 'stable'),
      'toolchain',
    );
    await fs.ensureDir(fs.pathContext.join(realHome, '.cargo', 'bin'));
    await fs.ensureDir(fs.pathContext.join(realHome, '.config', 'gh'));
    await fs.writeString(
      fs.pathContext.join(realHome, '.config', 'gh', 'hosts.yml'),
      'github.com',
    );
    await fs.ensureDir(fs.pathContext.join(realHome, '.cursor', 'global'));
    await fs.writeString(
      fs.pathContext.join(realHome, '.cursor', 'global', 'state.json'),
      '{}',
    );
  }

  group('CursorMemberHomePassthrough', () {
    test('remote mirror script links home entries and skips .cursor', () {
      final script = CursorMemberHomePassthrough.buildRemoteMirrorScript(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(script, contains("real_home='/home/user'"));
      expect(
        script,
        contains("member_home='/tp/workspace/ws/runtime/planner/cursor/home'"),
      );
      expect(script, contains(r'mkdir -p -- "$member_home/.config/cursor"'));
      expect(script, contains(r'find "$real_home"'));
      expect(script, contains("! -name '.cursor'"));
      expect(script, contains('ln -sfn'));
      expect(script, contains(".config"));
    });

    test('remote mirror script no-ops when homes match', () {
      final script = CursorMemberHomePassthrough.buildRemoteMirrorScript(
        realHomeRoot: realHome,
        memberHomeRoot: realHome,
      );
      expect(script.trim(), isEmpty);
    });

    test('symlinks real-home entries except .cursor', () async {
      await seedRealHome();
      await fs.ensureDir(memberHome);
      await fs.ensureDir(layout.cursorDir(memberHome));
      await fs.ensureDir(layout.configCursorDir(memberHome));

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.rustup'),
        ),
        fs.pathContext.join(realHome, '.rustup'),
      );
      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.cargo'),
        ),
        fs.pathContext.join(realHome, '.cargo'),
      );
      expect((await fs.stat(layout.cursorDir(memberHome))).isDirectory, isTrue);
      expect(
        (await fs.stat(layout.cursorDir(memberHome))).isSymlink,
        isFalse,
      );
      expect((await fs.stat(layout.configCursorDir(memberHome))).isDirectory, isTrue);
      expect(
        await fs.readString(
          fs.pathContext.join(layout.cursorDir(memberHome), 'probe.txt'),
        ),
        isNull,
      );
    });

    test('symlinks .config children except cursor', () async {
      await seedRealHome();
      await fs.ensureDir(memberHome);
      await fs.ensureDir(layout.configCursorDir(memberHome));
      await fs.writeString(
        layout.authJson(memberHome),
        '{"accessToken":"member"}',
      );

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.config', 'gh'),
        ),
        fs.pathContext.join(realHome, '.config', 'gh'),
      );
      expect(
        await fs.readString(layout.authJson(memberHome)),
        '{"accessToken":"member"}',
      );
      expect((await fs.stat(layout.configCursorDir(memberHome))).isSymlink, isFalse);
    });

    test('replaces orphan member-home dirs with symlinks', () async {
      await seedRealHome();
      await fs.ensureDir(memberHome);
      await fs.ensureDir(fs.pathContext.join(memberHome, '.rustup', 'orphan'));

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.rustup'),
        ),
        fs.pathContext.join(realHome, '.rustup'),
      );
      expect(
        await fs.readString(
          fs.pathContext.join(memberHome, '.rustup', 'orphan'),
        ),
        isNull,
      );
    });

    test('graduates entity orphan when real home has no matching dir yet', () async {
      await fs.ensureDir(realHome);
      await fs.ensureDir(memberHome);
      await fs.ensureDir(fs.pathContext.join(memberHome, '.rustup', 'toolchains'));
      await fs.writeString(
        fs.pathContext.join(memberHome, '.rustup', 'toolchains', 'stable'),
        'toolchain',
      );

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(
        await fs.readString(
          fs.pathContext.join(realHome, '.rustup', 'toolchains', 'stable'),
        ),
        'toolchain',
      );
      expect((await fs.stat(fs.pathContext.join(memberHome, '.rustup'))).isSymlink, isTrue);
      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.rustup'),
        ),
        fs.pathContext.join(realHome, '.rustup'),
      );
    });

    test('keeps correct dangling symlink when real home entry is gone', () async {
      await seedRealHome();
      await fs.ensureDir(memberHome);

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );
      await fs.removeRecursive(fs.pathContext.join(realHome, '.rustup'));

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.rustup'),
        ),
        fs.pathContext.join(realHome, '.rustup'),
      );
    });

    test('moves member-only entity orphan onto real home when rename succeeds', () async {
      await fs.ensureDir(realHome);
      await fs.ensureDir(memberHome);
      await fs.writeString(
        fs.pathContext.join(memberHome, '.only-member', 'cache'),
        'keep-me',
      );

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(
        await fs.readString(
          fs.pathContext.join(realHome, '.only-member', 'cache'),
        ),
        'keep-me',
      );
      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.only-member'),
        ),
        fs.pathContext.join(realHome, '.only-member'),
      );
    });

    test('falls back to delete and link when rename fails', () async {
      final failingFs = _RenameFailingFilesystem();
      final failingPassthrough = CursorMemberHomePassthrough(
        fs: failingFs,
        layout: CursorHomeLayout(pathContext: failingFs.pathContext),
      );

      await failingFs.ensureDir(realHome);
      await failingFs.ensureDir(memberHome);
      await failingFs.writeString(
        failingFs.pathContext.join(memberHome, '.rustup', 'orphan'),
        'lost',
      );

      await failingPassthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect((await failingFs.stat(failingFs.pathContext.join(realHome, '.rustup'))).exists, isFalse);
      expect(
        await failingFs.readSymlinkTarget(
          failingFs.pathContext.join(memberHome, '.rustup'),
        ),
        failingFs.pathContext.join(realHome, '.rustup'),
      );
    });

    test('mirror is idempotent', () async {
      await seedRealHome();
      await fs.ensureDir(memberHome);

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );
      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );

      expect(
        await fs.readSymlinkTarget(
          fs.pathContext.join(memberHome, '.rustup'),
        ),
        fs.pathContext.join(realHome, '.rustup'),
      );
    });

    test('no-ops when real and member home are the same', () async {
      await fs.ensureDir(realHome);
      await fs.ensureDir(layout.cursorDir(realHome));

      await passthrough.mirror(
        realHomeRoot: realHome,
        memberHomeRoot: realHome,
      );

      expect(fs.symlinks, isEmpty);
    });
  });
}

final class _RenameFailingFilesystem extends InMemoryFilesystem {
  @override
  Future<void> rename(String from, String to) async {
    throw StateError('rename failed');
  }
}
