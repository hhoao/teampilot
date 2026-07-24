import '../../../models/skill_install_recipe.dart';
import 'skill_acquire_context.dart';

class SkillStepResult {
  const SkillStepResult({
    required this.success,
    this.message = '',
  });

  final bool success;
  final String message;

  static const ok = SkillStepResult(success: true);
}

typedef SkillStepHandler =
    Future<SkillStepResult> Function(
      SkillInstallStep step,
      SkillAcquireContext ctx,
    );
