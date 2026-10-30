import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../state/stress_controller.dart';

/// About, privacy and the project disclaimer.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.showPrivacy = false});

  /// Scrolls straight to the privacy section when opened from that row.
  final bool showPrivacy;

  /// The single wording of the disclaimer, used wherever it appears.
  static const String disclaimer =
      'NeuroPulse is a student research and wellness prototype. Stress '
      'estimates are based on physiological signals and machine-learning '
      'models and are not medical diagnoses. This application is not intended '
      'to diagnose, treat, cure, or prevent disease.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(showPrivacy ? 'Privacy and disclaimer' : 'About'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!showPrivacy) ...[
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Icon(
                          Icons.monitor_heart_rounded,
                          size: 38,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'NeuroPulse',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'ECG-based stress level estimation with gamified '
                      'biofeedback',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _InfoRow(label: 'Version', value: '0.1.0'),
                          const Divider(height: 1),
                          _InfoRow(
                            label: 'Stress engine',
                            value: stress.engineName,
                          ),
                          const Divider(height: 1),
                          _InfoRow(
                            label: 'Engine version',
                            value: stress.modelVersion,
                          ),
                          const Divider(height: 1),
                          _InfoRow(
                            label: 'Data source',
                            value: stress.dataSourceName,
                          ),
                          const Divider(height: 1),
                          _InfoRow(label: 'Sensor', value: 'Not connected'),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const SectionHeader(title: 'How it works today'),
                    AppCard(
                      child: Text(
                        'This build runs on simulated physiological data and a '
                        'transparent demo scoring engine, so the full '
                        'experience can be used without hardware. When the ECG '
                        'front end and the trained model are ready they plug '
                        'into the same interfaces, and the screens you see '
                        'here do not change.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  const SectionHeader(title: 'Disclaimer'),
                  AppCard(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Text(disclaimer, style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Your data'),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bullet(
                          text:
                              'Everything is stored on this device only. '
                              'Nothing is uploaded anywhere.',
                        ),
                        _Bullet(
                          text:
                              'Your account, sessions, baseline and settings '
                              'live in local storage.',
                        ),
                        _Bullet(
                          text:
                              'You can export a copy or delete everything at '
                              'any time from Settings.',
                        ),
                        _Bullet(
                          text:
                              'NeuroPulse asks only for a name, email and '
                              'age, and no other personal information.',
                        ),
                      ],
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Text(
        value,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: AppSpacing.sm),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
