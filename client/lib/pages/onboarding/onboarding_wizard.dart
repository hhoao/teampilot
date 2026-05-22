import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/workspace_surface_layers.dart';
import 'steps/appearance_step.dart';
import 'steps/cli_step.dart';
import 'steps/default_provider_step.dart';
import 'steps/provider_import_step.dart';
import 'steps/ssh_step.dart';

enum OnboardingStepKind {
  appearance,
  ssh,
  cli,
  providerImport,
  defaultProvider,
}

List<OnboardingStepKind> onboardingStepsForPlatform() {
  if (Platform.isAndroid) {
    return const [
      OnboardingStepKind.appearance,
      OnboardingStepKind.ssh,
      OnboardingStepKind.cli,
      OnboardingStepKind.providerImport,
      OnboardingStepKind.defaultProvider,
    ];
  }
  return const [
    OnboardingStepKind.appearance,
    OnboardingStepKind.cli,
    OnboardingStepKind.providerImport,
    OnboardingStepKind.defaultProvider,
  ];
}

class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  late final List<OnboardingStepKind> _steps;
  var _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _steps = onboardingStepsForPlatform();
  }

  bool get _isFirstStep => _pageIndex <= 0;
  bool get _isLastStep => _pageIndex >= _steps.length - 1;

  void _goPrevious() {
    if (_isFirstStep) return;
    setState(() => _pageIndex -= 1);
  }

  void _goNext() {
    if (_isLastStep) {
      widget.onComplete();
      return;
    }
    setState(() => _pageIndex += 1);
  }

  void _skip() => _goNext();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.workspacePage,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'TP',
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(l10n.onboardingTitle, style: tt.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: KeyedSubtree(
                              key: ValueKey(_pageIndex),
                              child: _buildStep(_steps[_pageIndex]),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              TextButton(
                                onPressed: _skip,
                                child: Text(l10n.onboardingSkip),
                              ),
                              const Spacer(),
                              if (!_isFirstStep) ...[
                                OutlinedButton(
                                  onPressed: _goPrevious,
                                  child: Text(l10n.onboardingPrevious),
                                ),
                                const SizedBox(width: 12),
                              ],
                              FilledButton(
                                onPressed: _goNext,
                                child: Text(
                                  _isLastStep
                                      ? l10n.onboardingGetStarted
                                      : l10n.onboardingNext,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingStepKind kind) {
    return switch (kind) {
      OnboardingStepKind.appearance => const OnboardingAppearanceStep(),
      OnboardingStepKind.ssh => OnboardingSshStep(onContinue: _goNext),
      OnboardingStepKind.cli => const OnboardingCliStep(),
      OnboardingStepKind.providerImport => const OnboardingProviderImportStep(),
      OnboardingStepKind.defaultProvider => const OnboardingDefaultProviderStep(),
    };
  }
}
