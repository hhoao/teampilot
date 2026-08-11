import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/skill_invocation_syntax.dart';
import 'package:teampilot/services/cli/opencode/capabilities/skill_invocation_syntax.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_invocation_syntax_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  group('skillInvocationText', () {
    const defaultCap = DefaultSkillInvocationSyntaxCapability();
    const opencodeCap = OpencodeSkillInvocationSyntaxCapability();
    const codexCap = CodexSkillInvocationSyntaxCapability();

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
    test('all launch CLIs expose SkillInvocationSyntaxCapability', () {
      final registry = CliToolRegistry.builtIn();
      for (final cli in [
        CliTool.claude,
        CliTool.flashskyai,
        CliTool.codex,
        CliTool.opencode,
        CliTool.cursor,
      ]) {
        expect(
          registry.capability<SkillInvocationSyntaxCapability>(cli),
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
        final cap = registry.capability<SkillInvocationSyntaxCapability>(cli);
        expect(cap?.skillInvocationPrefix, '/', reason: '$cli');
      }
      expect(
        registry
            .capability<SkillInvocationSyntaxCapability>(CliTool.codex)
            ?.skillInvocationPrefix,
        r'$',
      );
    });

    test('opencode tool wires the space-prefixed syntax', () {
      final cap = CliToolRegistry.builtIn()
          .capability<SkillInvocationSyntaxCapability>(CliTool.opencode);
      expect(cap, isA<OpencodeSkillInvocationSyntaxCapability>());
      expect(cap?.skillInvocationText('using-git-worktrees'),
          ' /using-git-worktrees');
    });
  });
}
