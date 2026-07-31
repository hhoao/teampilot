import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/app/connection_mode_service.dart';
import '../../theme/workspace_surface_layers.dart';
import 'steps/appearance_step.dart';
import 'steps/cli_step.dart';
import 'steps/default_preset_step.dart';
import 'steps/provider_import_step.dart';

enum OnboardingStepKind {
  appearance,
  workHome,
  cli,
  providerImport,
  defaultPreset,
}

List<OnboardingStepKind> onboardingStepsForPlatform({
  bool? isAndroid,
  bool hasBoundAndroidWorkHome = false,
}) {
  final android = isAndroid ?? Platform.isAndroid;
  if (!android) {
    return const [
      OnboardingStepKind.appearance,
      OnboardingStepKind.cli,
      OnboardingStepKind.providerImport,
      OnboardingStepKind.defaultPreset,
    ];
  }
  if (hasBoundAndroidWorkHome) {
    return const [
      OnboardingStepKind.appearance,
      OnboardingStepKind.cli,
      OnboardingStepKind.providerImport,
      OnboardingStepKind.defaultPreset,
    ];
  }
  return const [
    OnboardingStepKind.appearance,
    OnboardingStepKind.workHome,
    OnboardingStepKind.cli,
    OnboardingStepKind.providerImport,
    OnboardingStepKind.defaultPreset,
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
  static const _maxPageViewportHeight = 520.0;
  static const _minPageViewportHeight = 280.0;
  /// Gap + footer buttons. Vertical page padding is subtracted separately.
  static const _footerReserve = 96.0;
  static const _pageVerticalPadding = 16.0;

  late final List<OnboardingStepKind> _steps;
  late final PageController _pageController;
  final _defaultPresetKey = GlobalKey<OnboardingDefaultPresetStepState>();
  var _pageIndex = 0;
  var _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _steps = onboardingStepsForPlatform(
      hasBoundAndroidWorkHome:
          context.read<ConnectionModeService>().hasBoundAndroidWorkHome,
    );
    _pageController = PageController();
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
      await _defaultPresetKey.currentState?.commitSelection();
      if (!mounted) return;
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
    if (!mounted) return;
    setState(() {
      _pageIndex = page;
      _isAnimating = false;
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
            // Padding sits inside the LayoutBuilder, so reserve it when
            // sizing the pinned PageView or the footer row overflows.
            final viewportHeight = math
                .min(
                  _maxPageViewportHeight,
                  constraints.maxHeight -
                      _footerReserve -
                      (_pageVerticalPadding * 2),
                )
                .clamp(_minPageViewportHeight, _maxPageViewportHeight);

            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: _pageVerticalPadding,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: viewportHeight,
                          child: PageView.builder(
                            controller: _pageController,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _steps.length,
                            itemBuilder: (context, index) {
                              return _OnboardingStepPage(
                                child: _buildStep(
                                  _steps[index],
                                  isActive: index == _pageIndex,
                                ),
                              );
                            },
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingStepKind kind, {required bool isActive}) {
    return switch (kind) {
      OnboardingStepKind.appearance => OnboardingAppearanceStep(
        isActive: isActive,
      ),
      OnboardingStepKind.workHome => const SizedBox.shrink(),
      OnboardingStepKind.cli => OnboardingCliStep(isActive: isActive),
      OnboardingStepKind.providerImport => OnboardingProviderImportStep(
        isActive: isActive,
      ),
      OnboardingStepKind.defaultPreset => OnboardingDefaultPresetStep(
        key: _defaultPresetKey,
        isActive: isActive,
      ),
    };
  }
}

class _OnboardingStepPage extends StatefulWidget {
  const _OnboardingStepPage({required this.child});

  final Widget child;

  @override
  State<_OnboardingStepPage> createState() => _OnboardingStepPageState();
}

class _OnboardingStepPageState extends State<_OnboardingStepPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
