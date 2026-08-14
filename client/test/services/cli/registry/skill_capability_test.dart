import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/skill.dart';
import 'package:teampilot/services/cli/opencode/capabilities/skill.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  // CliToolRegistry.builtIn() exists and calls registerBuiltInCliTools internally.
  CliToolRegistry buildRegistry() => CliToolRegistry.builtIn();

  test('every launchable CLI exposes a SkillCapability', () {
    final registry = buildRegistry();
    for (final cli in CliTool.values) {
      final cap = registry.capability<SkillCapability>(cli);
      expect(cap, isNotNull, reason: '$cli must expose SkillCapability');
    }
  });

  test(
    'opencode uses "skill" subdir; cursor uses "skills-cursor"; others use "skills"',
    () {
      final registry = buildRegistry();
      expect(
        registry.capability<SkillCapability>(CliTool.opencode)!.skillsSubdir,
        'skill',
      );
      expect(
        registry.capability<SkillCapability>(CliTool.cursor)!.skillsSubdir,
        'skills-cursor',
      );
      for (final cli in CliTool.values.where(
        (c) => c != CliTool.opencode && c != CliTool.cursor,
      )) {
        expect(
          registry.capability<SkillCapability>(cli)!.skillsSubdir,
          'skills',
          reason: '$cli should use the default skills subdir',
        );
      }
    },
  );

  test('every launchable CLI links skills as directories', () {
    final registry = buildRegistry();
    for (final cli in CliTool.values) {
      expect(
        registry
            .capability<SkillCapability>(cli)!
            .skillsRepresentation,
        ResourceRepresentation.linkedDirectory,
        reason: '$cli',
      );
    }
  });

  group('skillInvocationText', () {
    const defaultCap = DefaultSkillInvocationSyntaxCapability();
    const opencodeCap = OpencodeSkillCapability();
    const codexCap = CodexSkillCapability();

    test('default renders Claude-style /name', () {
      expect(defaultCap.skillInvocationText('using-git-worktrees'),
          '/using-git-worktrees');
      // Namespace is ignored by slash CLIs.
      expect(
        defaultCap.skillInvocationText(
          'using-git-worktrees',
          namespace: 'superpowers',
        ),
        '/using-git-worktrees',
      );
    });

    test('opencode prepends a space so the / is not glued to text', () {
      expect(opencodeCap.skillInvocationText('using-git-worktrees'),
          ' /using-git-worktrees');
    });

    test(r'codex renders $name and namespaced $plugin:name', () {
      expect(codexCap.skillInvocationText('using-git-worktrees'),
          r'$using-git-worktrees');
      expect(
        codexCap.skillInvocationText(
          'using-git-worktrees',
          namespace: 'superpowers',
        ),
        r'$superpowers:using-git-worktrees',
      );
    });

    test(r'codex declares a $ prefix', () {
      expect(codexCap.skillInvocationPrefix, r'$');
    });
  });

  group('registry wiring', () {
    test('all launch CLIs expose SkillCapability', () {
      final registry = CliToolRegistry.builtIn();
      for (final cli in [
        CliTool.claude,
        CliTool.flashskyai,
        CliTool.codex,
        CliTool.opencode,
        CliTool.cursor,
      ]) {
        expect(
          registry.capability<SkillCapability>(cli),
          isNotNull,
          reason: '$cli',
        );
      }
    });

    test(r'only codex uses the $ prefix', () {
      final registry = CliToolRegistry.builtIn();
      for (final cli in [
        CliTool.claude,
        CliTool.flashskyai,
        CliTool.opencode,
        CliTool.cursor,
      ]) {
        final cap = registry.capability<SkillCapability>(cli);
        expect(cap?.skillInvocationPrefix, '/', reason: '$cli');
      }
      expect(
        registry
            .capability<SkillCapability>(CliTool.codex)
            ?.skillInvocationPrefix,
        r'$',
      );
    });

    test('opencode tool wires the space-prefixed syntax', () {
      final cap = CliToolRegistry.builtIn()
          .capability<SkillCapability>(CliTool.opencode);
      expect(cap, isA<OpencodeSkillCapability>());
      expect(cap?.skillInvocationText('using-git-worktrees'),
          ' /using-git-worktrees');
    });
  });
}
