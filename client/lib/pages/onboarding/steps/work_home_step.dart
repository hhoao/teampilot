import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/ssh_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/app/connection_mode_service.dart';
import '../../ssh_profiles_page.dart';
import '../../termux/termux_setup_page.dart';
import '../../termux/work_environment_chooser_page.dart';
import 'onboarding_step_scaffold.dart';

enum _WorkHomeSubpage { chooser, termux, ssh }

/// Android onboarding: bind Termux or remote SSH before CLI detection.
class OnboardingWorkHomeStep extends StatefulWidget {
  const OnboardingWorkHomeStep({super.key, required this.onBound});

  final VoidCallback onBound;

  @override
  State<OnboardingWorkHomeStep> createState() => _OnboardingWorkHomeStepState();
}

class _OnboardingWorkHomeStepState extends State<OnboardingWorkHomeStep> {
  var _subpage = _WorkHomeSubpage.chooser;
  var _didNotify = false;

  void _notifyBound() {
    if (_didNotify) return;
    _didNotify = true;
    widget.onBound();
  }

  void _goChooser() {
    setState(() => _subpage = _WorkHomeSubpage.chooser);
  }

  @override
  Widget build(BuildContext context) {
    // Mirror StartupGate: rebuild when Connect updates prefs and/or the
    // selected SSH profile, then read derived bind flags. Do not watch
    // ConnectionModeService (it is not a Listenable).
    context.watch<SessionPreferencesCubit>();
    context.watch<SshProfileCubit>();
    final bound =
        context.read<ConnectionModeService>().hasBoundAndroidWorkHome;
    if (!_didNotify && bound) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifyBound();
      });
    }

    final l10n = context.l10n;
    return OnboardingStepScaffold(
      title: l10n.onboardingWorkHomeTitle,
      subtitle: l10n.onboardingWorkHomeSubtitle,
      scrollBody: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_subpage != _WorkHomeSubpage.chooser)
            Align(
              alignment: Alignment.centerLeft,
              child: TpIconButton(
                key: const Key('work_home_back'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icons.arrow_back,
                size: TpIconButton.chromeAlignedSize(context),
                onTap: _goChooser,
              ),
            ),
          Expanded(child: _buildSubpage()),
        ],
      ),
    );
  }

  Widget _buildSubpage() {
    return switch (_subpage) {
      _WorkHomeSubpage.chooser => WorkEnvironmentChooserPage(
        embedded: true,
        onChooseTermux: () {
          setState(() => _subpage = _WorkHomeSubpage.termux);
        },
        onChooseSsh: () {
          setState(() => _subpage = _WorkHomeSubpage.ssh);
        },
      ),
      _WorkHomeSubpage.termux => TermuxSetupPage(
        embedded: true,
        onHomeBound: _notifyBound,
      ),
      _WorkHomeSubpage.ssh => const SshProfilesPage(embedded: true),
    };
  }
}
