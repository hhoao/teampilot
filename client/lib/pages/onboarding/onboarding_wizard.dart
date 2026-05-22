import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
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

String onboardingStepLabel(BuildContext context, OnboardingStepKind kind) {
  final l10n = context.l10n;
  return switch (kind) {
    OnboardingStepKind.appearance => l10n.onboardingStepAppearance,
    OnboardingStepKind.ssh => l10n.onboardingStepSsh,
    OnboardingStepKind.cli => l10n.onboardingStepCli,
    OnboardingStepKind.providerImport => l10n.onboardingStepProviderImport,
    OnboardingStepKind.defaultProvider => l10n.onboardingStepDefaultProvider,
  };
}

class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  late final List<OnboardingStepKind> _steps;
  late final PageController _pageController;
  var _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _steps = onboardingStepsForPlatform();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLastStep => _pageIndex >= _steps.length - 1;

  void _goNext() {
    if (_isLastStep) {
      widget.onComplete();
      return;
    }
    final next = _pageIndex + 1;
    setState(() => _pageIndex = next);
    unawaited(
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _skip() => _goNext();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
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
                      const Spacer(),
                      Text(
                        l10n.onboardingProgress(
                          _pageIndex + 1,
                          _steps.length,
                        ),
                        style: tt.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (_pageIndex + 1) / _steps.length,
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        InputChip(
                          label: Text(onboardingStepLabel(context, _steps[i])),
                          selected: i == _pageIndex,
                          onSelected: null,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _steps.length,
                      itemBuilder: (context, index) {
                        return SingleChildScrollView(
                          child: _buildStep(_steps[index]),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _skip,
                        child: Text(l10n.onboardingSkip),
                      ),
                      const Spacer(),
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
