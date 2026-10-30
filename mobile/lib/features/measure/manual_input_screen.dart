import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/physiological_input_packet.dart';
import '../../domain/stress/stress_level.dart';

/// Manual entry of physiological values.
///
/// The point of this screen is that the project is not blocked on hardware.
/// Anything the wearable will eventually send can be typed in, and the app
/// treats it identically from here on.
///
/// Only heart rate is required. Every other field may be left blank, and blank
/// means **absent**, not zero - an empty GSR field produces a packet with no
/// GSR, which the rest of the app reports as "Not available". That is the same
/// behaviour as a wearable that has no GSR sensor fitted, so the two paths stay
/// consistent.
///
/// Values entered here are tagged [PhysiologicalSource.manual] permanently.
/// The app never presents them as measurements it took.
class ManualInputScreen extends StatefulWidget {
  const ManualInputScreen({super.key});

  @override
  State<ManualInputScreen> createState() => _ManualInputScreenState();
}

class _ManualInputScreenState extends State<ManualInputScreen> {
  final _formKey = GlobalKey<FormState>();

  final _hr = TextEditingController();
  final _meanRR = TextEditingController();
  final _rmssd = TextEditingController();
  final _sdnn = TextEditingController();
  final _pnn50 = TextEditingController();
  final _gsr = TextEditingController();
  final _gsrPeaks = TextEditingController();
  final _accelX = TextEditingController();
  final _accelY = TextEditingController();
  final _accelZ = TextEditingController();
  final _gyroX = TextEditingController();
  final _gyroY = TextEditingController();
  final _gyroZ = TextEditingController();
  final _battery = TextEditingController();
  final _context = TextEditingController();

  int? _stressRating;

  @override
  void dispose() {
    for (final controller in [
      _hr, _meanRR, _rmssd, _sdnn, _pnn50, _gsr, _gsrPeaks,
      _accelX, _accelY, _accelZ, _gyroX, _gyroY, _gyroZ, _battery, _context,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _parse(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  int? _parseInt(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  /// Fills the form with values that look like the chosen level.
  ///
  /// Quick Demo, per section 11 of the brief. These numbers are invented for
  /// demonstration. They are not medically validated and not measurements, and
  /// the resulting reading is still tagged as Manual so history stays honest
  /// about where it came from.
  void _applyScenario(StressLevel level) {
    final t = (level.number - 1) / 4;

    setState(() {
      _hr.text = (62 + 32 * t).toStringAsFixed(0);
      _meanRR.text = (60000 / (62 + 32 * t)).toStringAsFixed(0);
      _rmssd.text = (58 - 42 * t).toStringAsFixed(0);
      _sdnn.text = (68 - 44 * t).toStringAsFixed(0);
      _pnn50.text = (26 - 23 * t).clamp(0, 100).toStringAsFixed(0);
      _gsr.text = (1.8 + 3.4 * t).toStringAsFixed(1);
      _gsrPeaks.text = (1 + 6 * t).toStringAsFixed(0);
      _accelX.text = '0.02';
      _accelY.text = '0.08';
      _accelZ.text = '0.98';
      _gyroX.text = '0.10';
      _gyroY.text = '0.20';
      _gyroZ.text = '0.10';
      _battery.text = '87';
      _stressRating = level.number;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Filled with demo values for ${StressLevelConfig.of(level).title}. '
          'These are illustrative, not measurements.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final hr = _parse(_hr);
    final packet = PhysiologicalInputPacket(
      timestamp: DateTime.now(),
      source: PhysiologicalSource.manual,
      heartRate: hr,
      // Derived from heart rate when not supplied, because mean R-R is exactly
      // 60000/HR by definition. This is arithmetic, not an invented reading.
      meanRR: _parse(_meanRR) ?? (hr != null && hr > 0 ? 60000 / hr : null),
      rmssd: _parse(_rmssd),
      sdnn: _parse(_sdnn),
      pnn50: _parse(_pnn50),
      gsrValue: _parse(_gsr),
      gsrPeaks: _parseInt(_gsrPeaks),
      accelX: _parse(_accelX),
      accelY: _parse(_accelY),
      accelZ: _parse(_accelZ),
      gyroX: _parse(_gyroX),
      gyroY: _parse(_gyroY),
      gyroZ: _parse(_gyroZ),
      batteryPercentage: _parseInt(_battery),
      userStressRating: _stressRating,
      sessionContext: _context.text.trim().isEmpty
          ? null
          : _context.text.trim(),
    );

    Navigator.of(context).pop(packet);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Input')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    color: theme.colorScheme.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Enter the values you have. Only heart rate is required '
                      '- anything left blank is recorded as not available, '
                      'never as zero.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            _QuickDemoPicker(onSelected: _applyScenario),
            const SizedBox(height: AppSpacing.lg),

            _Group(
              title: 'Cardiovascular',
              icon: Icons.favorite_outline,
              initiallyExpanded: true,
              children: [
                _Field(
                  controller: _hr,
                  label: 'Heart Rate',
                  unit: 'BPM',
                  required: true,
                  min: 20,
                  max: 250,
                ),
                _Field(
                  controller: _meanRR,
                  label: 'Mean R-R',
                  unit: 'ms',
                  hint: 'Leave blank to derive from heart rate',
                  min: 200,
                  max: 3000,
                ),
                _Field(
                  controller: _rmssd,
                  label: 'RMSSD',
                  unit: 'ms',
                  min: 0,
                  max: 1000,
                ),
                _Field(
                  controller: _sdnn,
                  label: 'SDNN',
                  unit: 'ms',
                  min: 0,
                  max: 1000,
                ),
                _Field(
                  controller: _pnn50,
                  label: 'pNN50',
                  unit: '%',
                  min: 0,
                  max: 100,
                ),
              ],
            ),

            _Group(
              title: 'GSR / EDA',
              icon: Icons.water_drop_outlined,
              children: [
                _Field(
                  controller: _gsr,
                  label: 'GSR level',
                  unit: 'uS',
                  min: 0,
                  max: 1000,
                ),
                _Field(
                  controller: _gsrPeaks,
                  label: 'GSR peaks',
                  unit: 'count',
                  integer: true,
                  min: 0,
                  max: 1000,
                ),
              ],
            ),

            _Group(
              title: 'Movement',
              icon: Icons.directions_walk_outlined,
              subtitle:
                  'Context only. Movement is not treated as stress anywhere '
                  'in the app.',
              children: [
                _Field(
                  controller: _accelX,
                  label: 'Accelerometer X',
                  unit: 'g',
                  min: -16,
                  max: 16,
                  signed: true,
                ),
                _Field(
                  controller: _accelY,
                  label: 'Accelerometer Y',
                  unit: 'g',
                  min: -16,
                  max: 16,
                  signed: true,
                ),
                _Field(
                  controller: _accelZ,
                  label: 'Accelerometer Z',
                  unit: 'g',
                  min: -16,
                  max: 16,
                  signed: true,
                ),
                _Field(
                  controller: _gyroX,
                  label: 'Gyroscope X',
                  unit: 'dps',
                  min: -2000,
                  max: 2000,
                  signed: true,
                ),
                _Field(
                  controller: _gyroY,
                  label: 'Gyroscope Y',
                  unit: 'dps',
                  min: -2000,
                  max: 2000,
                  signed: true,
                ),
                _Field(
                  controller: _gyroZ,
                  label: 'Gyroscope Z',
                  unit: 'dps',
                  min: -2000,
                  max: 2000,
                  signed: true,
                ),
              ],
            ),

            _Group(
              title: 'Device',
              icon: Icons.battery_std_outlined,
              children: [
                _Field(
                  controller: _battery,
                  label: 'Battery',
                  unit: '%',
                  integer: true,
                  min: 0,
                  max: 100,
                ),
              ],
            ),

            _Group(
              title: 'Context',
              icon: Icons.notes_outlined,
              subtitle:
                  'Your own rating is self-report. It is stored alongside the '
                  'reading and never used to produce it.',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How stressed do you feel?',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          for (final level in StressLevel.values)
                            ChoiceChip(
                              label: Text('${level.number}'),
                              selected: _stressRating == level.number,
                              onSelected: (selected) => setState(() {
                                _stressRating = selected ? level.number : null;
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: TextFormField(
                    controller: _context,
                    decoration: const InputDecoration(
                      labelText: 'Session context',
                      hintText: 'e.g. before exam',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('ANALYZE'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

/// Quick Demo scenario picker (section 11).
class _QuickDemoPicker extends StatelessWidget {
  const _QuickDemoPicker({required this.onSelected});

  final void Function(StressLevel level) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: 20,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Quick Demo', style: theme.textTheme.titleSmall),
              const Spacer(),
              const DemoBadge(label: 'Demo values'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Fill the form with illustrative values for a stress level. '
            'For demonstration only - not medically validated.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final level in StressLevel.values)
                OutlinedButton(
                  onPressed: () => onSelected(level),
                  child: Text('Level ${level.number}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final String? subtitle;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(title, style: theme.textTheme.titleSmall),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!, style: theme.textTheme.bodySmall),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: children,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.unit,
    this.hint,
    this.required = false,
    this.integer = false,
    this.signed = false,
    required this.min,
    required this.max,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final String? hint;
  final bool required;
  final bool integer;
  final bool signed;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !integer,
          signed: signed,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(signed ? r'[0-9.\-]' : r'[0-9.]'),
          ),
        ],
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          suffixText: unit,
          hintText: hint,
        ),
        validator: (value) {
          final text = (value ?? '').trim();
          if (text.isEmpty) {
            return required ? '$label is required' : null;
          }
          final parsed = double.tryParse(text);
          if (parsed == null) return 'Enter a number';
          if (parsed < min || parsed > max) {
            return 'Must be between ${_fmt(min)} and ${_fmt(max)}';
          }
          return null;
        },
      ),
    );
  }

  static String _fmt(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
}
