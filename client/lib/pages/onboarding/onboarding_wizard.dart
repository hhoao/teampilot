import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
  static const _pageAnimationDuration = Duration(milliseconds: 300);
  static const _minPageViewportHeight = 280;
  static const _maxPageViewportHeight = 520;
  static const _footerReserve = 96;

  late final List<OnboardingStepKind> _steps;
  late final List<GlobalKey> _stepMeasureKeys;
  late final PageController _pageController;
  var _pageIndex = 0;
  var _isAnimating = false;
  var _pageViewportHeight = _minPageViewportHeight.toDouble();

  @override
  void initState() {
    super.initState();
    _steps = onboardingStepsForPlatform();
    _stepMeasureKeys = List.generate(_steps.length, (_) => GlobalKey());
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncViewportHeightForPage(_pageIndex);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isFirstStep => _pageIndex <= 0;
  bool get _isLastStep => _pageIndex >= _steps.length - 1;

  Future<void> _goPrevious() async {
    if (_isAnimating || _isFirstStep) return;
    await _animateToPage(_pageIndex - 1);
  }

  Future<void> _goNext() async {
    if (_isAnimating) return;
    if (_isLastStep) {
      widget.onComplete();
      return;
    }
    await _animateToPage(_pageIndex + 1);
  }

  void _skip() => unawaited(_goNext());

  Future<void> _animateToPage(int page) async {
    if (!_pageController.hasClients) return;
    setState(() => _isAnimating = true);
    await _pageController.animateToPage(
      page,
      duration: _pageAnimationDuration,
      curve: Curves.easeOutCubic,
    );
    if (mounted) {
      setState(() => _isAnimating = false);
    }
  }

  void _syncViewportHeightForPage(int index) {
    if (!mounted || _isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isAnimating) return;
      final box =
          _stepMeasureKeys[index].currentContext?.findRenderObject()
              as RenderBox?;
      if (box == null || !box.hasSize) return;

      final nextHeight = box.size.height.clamp(
        _minPageViewportHeight.toDouble(),
        _maxPageViewportHeight.toDouble(),
      );
      if ((_pageViewportHeight - nextHeight).abs() <= 1) return;
      setState(() => _pageViewportHeight = nextHeight);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final navigationLocked = _isAnimating;

    return Scaffold(
      backgroundColor: cs.workspacePage,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxViewportHeight = math
                .min(
                  _maxPageViewportHeight.toDouble(),
                  constraints.maxHeight - _footerReserve,
                )
                .clamp(
                  _minPageViewportHeight.toDouble(),
                  _maxPageViewportHeight.toDouble(),
                );
            final viewportHeight = math.min(_pageViewportHeight, maxViewportHeight);

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
                          AnimatedSize(
                            duration: _pageAnimationDuration,
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              height: viewportHeight,
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                onPageChanged: (index) {
                                  setState(() => _pageIndex = index);
                                  _syncViewportHeightForPage(index);
                                },
                                children: [
                                  for (var i = 0; i < _steps.length; i++)
                                    NotificationListener<SizeChangedLayoutNotification>(
                                      onNotification: (_) {
                                        if (i == _pageIndex) {
                                          _syncViewportHeightForPage(i);
                                        }
                                        return false;
                                      },
                                      child: SizeChangedLayoutNotifier(
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: SingleChildScrollView(
                                            child: KeyedSubtree(
                                              key: _stepMeasureKeys[i],
                                              child: _buildStep(_steps[i]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              TextButton(
                                onPressed: navigationLocked ? null : _skip,
                                child: Text(l10n.onboardingSkip),
                              ),
                              const Spacer(),
                              if (!_isFirstStep) ...[
                                OutlinedButton(
                                  onPressed: navigationLocked
                                      ? null
                                      : () => unawaited(_goPrevious()),
                                  child: Text(l10n.onboardingPrevious),
                                ),
                                const SizedBox(width: 12),
                              ],
                              FilledButton(
                                onPressed: navigationLocked
                                    ? null
                                    : () => unawaited(_goNext()),
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
      OnboardingStepKind.ssh => OnboardingSshStep(
        onContinue: () => unawaited(_goNext()),
      ),
      OnboardingStepKind.cli => const OnboardingCliStep(),
      OnboardingStepKind.providerImport =>
        const OnboardingProviderImportStep(),
      OnboardingStepKind.defaultProvider =>
        const OnboardingDefaultProviderStep(),
    };
  }
}
