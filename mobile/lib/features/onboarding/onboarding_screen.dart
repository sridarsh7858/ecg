import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/motion.dart';
import '../../core/widgets/app_widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';

/// Four short slides. Skippable, and never shown again once completed.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.favorite_rounded,
      title: 'Welcome to NeuroPulse',
      body:
          'A calm space to check in with yourself, built around your heart '
          'rhythm.',
    ),
    _OnboardingPage(
      icon: Icons.insights_rounded,
      title: 'Understand your current stress',
      body:
          'A short check-in estimates where you are on a simple five-level '
          'scale, with the numbers behind it.',
    ),
    _OnboardingPage(
      icon: Icons.sports_esports_rounded,
      title: 'Play calming experiences',
      body:
          'Guided breathing and gentle games, suggested to match how you '
          'are feeling right now.',
    ),
    _OnboardingPage(
      icon: Icons.trending_down_rounded,
      title: 'Track your progress',
      body:
          'Every session is saved so you can see how things shift over days '
          'and weeks.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLastPage => _page == _pages.length - 1;

  /// Marks onboarding done and lets the root gate decide what comes next.
  ///
  /// Deliberately does NOT push a screen: this widget is rendered *by* the
  /// gate, so replacing the route would tear the gate out of the tree and
  /// nothing would be left watching [AuthController] to swap in the shell
  /// once the user signs in.
  Future<void> _finish() => context.read<AuthController>().completeOnboarding();

  void _next(bool reduceMotion) {
    if (_isLastPage) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: AppMotion.scale(AppMotion.medium, reduceMotion: reduceMotion),
      curve: AppMotion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        context.watch<SettingsController>().reduceMotion ||
        AppMotion.platformPrefersReducedMotion(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => _pages[index],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: AppMotion.scale(
                            AppMotion.fast,
                            reduceMotion: reduceMotion,
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 7,
                          width: i == _page ? 24 : 7,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _next(reduceMotion),
                      child: Text(_isLastPage ? 'Get Started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PageBody(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.20),
                  theme.colorScheme.tertiary.withValues(alpha: 0.14),
                ],
              ),
            ),
            child: Icon(icon, size: 58, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
