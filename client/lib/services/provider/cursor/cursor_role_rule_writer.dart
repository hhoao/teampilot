import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../../session/member_role_provision.dart';
import 'cursor_home_layout.dart';

/// Writes Cursor member identity to `~/.cursor/rules/role.mdc`.
///
/// Cursor has no `--system-prompt` flag; persona lives in an always-applied
/// rule under the session fake HOME (simple and mixed).
final class CursorRoleRuleWriter {
  CursorRoleRuleWriter({
    required Filesystem fs,
    CursorHomeLayout? layout,
  }) : _fs = fs,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext);

  final Filesystem _fs;
  final CursorHomeLayout _layout;

  /// Formats [body] as a Cursor rule with `alwaysApply: true` frontmatter.
  static String format(String body) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('alwaysApply: true')
      ..writeln('---')
      ..writeln();
    if (body.isNotEmpty) buffer.writeln(body);
    return buffer.toString();
  }

  /// Syncs [member] identity into [memberHome] `/.cursor/rules/role.mdc`.
  /// Removes the file when the composed prompt is empty. Returns the path
  /// when written.
  Future<String?> sync({
    required String memberHome,
    required TeamMemberConfig member,
    bool forceTeamLeadDelegateMode = false,
    bool mixed = false,
    bool pushDelivery = false,
  }) async {
    final path = _layout.roleRule(memberHome);
    final body = MemberRoleProvision.composeRolePrompt(
      member: member,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: mixed,
      pushDelivery: pushDelivery,
    ).trim();
    final stat = await _fs.stat(path);
    if (body.isEmpty) {
      if (stat.exists) {
        await _fs.removeRecursive(path);
      }
      return null;
    }
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(path, format(body));
    return path;
  }
}
