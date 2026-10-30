import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/local/local_store.dart';
import '../../../data/models/game_session.dart';
import '../../../domain/games/game_catalog.dart';
import '../../../state/settings_controller.dart';
import '../../../state/stress_controller.dart';
import '../widgets/game_scaffold.dart';

/// Things that can be placed in the garden.
enum GardenItem {
  stone('Stone', Icons.circle, 0),
  flower('Flower', Icons.local_florist_rounded, 0),
  water('Water', Icons.water_drop_rounded, 0),
  grass('Grass', Icons.grass_rounded, 2),
  lantern('Lantern', Icons.light_rounded, 5);

  const GardenItem(this.label, this.icon, this.sessionsToUnlock);

  final String label;
  final IconData icon;

  /// Completed game sessions needed before this item becomes available.
  final int sessionsToUnlock;

  bool isUnlocked(int sessionsPlayed) => sessionsPlayed >= sessionsToUnlock;
}

/// One placed object. Coordinates are 0..1 fractions of the canvas so the
/// garden survives rotation and different screen sizes.
class GardenObject {
  const GardenObject({
    required this.item,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
  });

  final GardenItem item;
  final double x;
  final double y;
  final double scale;
  final double rotation;

  Map<String, dynamic> toJson() => {
    'item': item.name,
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
  };

  static GardenObject? fromJson(Map<String, dynamic> json) {
    GardenItem? item;
    for (final candidate in GardenItem.values) {
      if (candidate.name == json['item']) item = candidate;
    }
    if (item == null) return null;
    return GardenObject(
      item: item,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      scale: (json['scale'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
    );
  }
}

/// A calm, open-ended space. Tap to place, long-press an object to remove it.
///
/// There is nothing to win. The garden persists between sessions, so it builds
/// up over time.
class ZenGardenScreen extends StatefulWidget {
  const ZenGardenScreen({super.key});

  @override
  State<ZenGardenScreen> createState() => _ZenGardenScreenState();
}

class _ZenGardenScreenState extends State<ZenGardenScreen> {
  final math.Random _random = math.Random();
  final List<GardenObject> _objects = [];

  late final DateTime _startedAt;
  late final LocalStore _store;
  late final int _sessionsPlayed;
  late final int _objectsAtStart;

  GardenItem _selected = GardenItem.stone;
  bool _finished = false;

  /// Placing this many objects counts the session as complete.
  static const int _placementsForCompletion = 6;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    final controller = context.read<StressController>();
    _sessionsPlayed = controller.totalGamesPlayed;
    _store = context.read<LocalStore>();
    _load();
    _objectsAtStart = _objects.length;
  }

  void _load() {
    final stored = _store.getObject(LocalStore.keyGarden);
    final list = stored?['objects'];
    if (list is! List) return;
    for (final entry in list) {
      if (entry is! Map) continue;
      final object = GardenObject.fromJson(Map<String, dynamic>.from(entry));
      if (object != null) _objects.add(object);
    }
  }

  Future<void> _save() {
    return _store.setObject(LocalStore.keyGarden, {
      'objects': _objects.map((o) => o.toJson()).toList(),
    });
  }

  void _place(Offset position, Size size) {
    if (_finished) return;
    setState(() {
      _objects.add(
        GardenObject(
          item: _selected,
          x: (position.dx / size.width).clamp(0.03, 0.97),
          y: (position.dy / size.height).clamp(0.05, 0.95),
          // Small random variation so a row of stones never looks stamped.
          scale: 0.82 + _random.nextDouble() * 0.45,
          rotation: (_random.nextDouble() - 0.5) * 0.6,
        ),
      );
    });
    if (context.read<SettingsController>().hapticsEnabled) {
      HapticFeedback.selectionClick();
    }
    _save();
  }

  void _removeNearest(Offset position, Size size) {
    if (_objects.isEmpty) return;
    final target = Offset(position.dx / size.width, position.dy / size.height);

    var bestIndex = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _objects.length; i++) {
      final object = _objects[i];
      final distance = (Offset(object.x, object.y) - target).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex == -1 || bestDistance > 0.10) return;
    setState(() => _objects.removeAt(bestIndex));
    _save();
  }

  void _undo() {
    if (_objects.isEmpty) return;
    setState(() => _objects.removeLast());
    _save();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the garden?'),
        content: const Text('Everything you have placed will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _objects.clear());
    await _save();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;

    final placed = math.max(0, _objects.length - _objectsAtStart);
    Navigator.of(context).pop(
      GameResult(
        gameId: GameIds.zenGarden,
        duration: DateTime.now().difference(_startedAt),
        score: _objects.length * 5,
        completion: (placed / _placementsForCompletion).clamp(0.0, 1.0),
        metrics: {'placedThisSession': placed, 'gardenSize': _objects.length},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = GameCatalog.zenGarden;
    final placedThisSession = math.max(0, _objects.length - _objectsAtStart);

    return GameScaffold(
      game: game,
      onEnd: _finish,
      hud: [
        GameHudItem(label: 'In your garden', value: '${_objects.length}'),
        GameHudItem(label: 'Placed now', value: '$placedThisSession'),
        GameHudItem(
          label: 'Unlocked',
          value:
              '${GardenItem.values.where((i) => i.isUnlocked(_sessionsPlayed)).length}'
              '/${GardenItem.values.length}',
        ),
      ],
      footer: Column(
        children: [
          _Palette(
            selected: _selected,
            sessionsPlayed: _sessionsPlayed,
            accent: game.accent,
            onSelected: (item) => setState(() => _selected = item),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _objects.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo_rounded, size: 20),
                  label: const Text('UNDO'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _objects.isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: const Text('CLEAR'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('DONE'),
                ),
              ),
            ],
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _place(details.localPosition, size),
              onLongPressStart: (details) =>
                  _removeNearest(details.localPosition, size),
              child: Semantics(
                label:
                    'Garden canvas. Tap to place a ${_selected.label}, '
                    'long press to remove an object.',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: CustomPaint(
                    painter: _GardenPainter(
                      objects: _objects,
                      sand: theme.brightness == Brightness.dark
                          ? const Color(0xFF1C201B)
                          : const Color(0xFFF2EDE1),
                      rake: theme.brightness == Brightness.dark
                          ? const Color(0xFF262B24)
                          : const Color(0xFFE7E0CF),
                    ),
                    child: _objects.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Text(
                                'Tap anywhere to place a ${_selected.label.toLowerCase()}.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.expand(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette({
    required this.selected,
    required this.sessionsPlayed,
    required this.accent,
    required this.onSelected,
  });

  final GardenItem selected;
  final int sessionsPlayed;
  final Color accent;
  final ValueChanged<GardenItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in GardenItem.values) ...[
            Builder(
              builder: (context) {
                final unlocked = item.isUnlocked(sessionsPlayed);
                final isSelected = item == selected && unlocked;

                return Semantics(
                  selected: isSelected,
                  label: unlocked
                      ? item.label
                      : '${item.label}, locked. Play '
                            '${item.sessionsToUnlock} sessions to unlock.',
                  child: Tooltip(
                    message: unlocked
                        ? item.label
                        : 'Unlocks after ${item.sessionsToUnlock} sessions',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: unlocked ? () => onSelected(item) : null,
                      child: Container(
                        width: 68,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accent.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: isSelected
                                ? accent
                                : theme.colorScheme.outlineVariant,
                            width: isSelected ? 1.6 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              unlocked ? item.icon : Icons.lock_outline_rounded,
                              size: 22,
                              color: unlocked
                                  ? (isSelected
                                        ? accent
                                        : theme.colorScheme.onSurfaceVariant)
                                  : theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: unlocked
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.outline,
                                fontWeight: isSelected ? FontWeight.w700 : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _GardenPainter extends CustomPainter {
  _GardenPainter({
    required this.objects,
    required this.sand,
    required this.rake,
  });

  final List<GardenObject> objects;
  final Color sand;
  final Color rake;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = sand);

    // Raked sand lines, the visual signature of a zen garden.
    final rakePaint = Paint()
      ..color = rake
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (var i = 0; i < 14; i++) {
      final y = size.height * (i + 0.5) / 14;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 12) {
        path.lineTo(x, y + math.sin(x / 46 + i) * 3.2);
      }
      canvas.drawPath(path, rakePaint);
    }

    // Painter order is placement order, so newer objects sit on top.
    for (final object in objects) {
      final centre = Offset(object.x * size.width, object.y * size.height);
      final radius = size.shortestSide * 0.045 * object.scale;

      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(object.rotation);

      switch (object.item) {
        case GardenItem.stone:
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: radius * 2.2,
              height: radius * 1.6,
            ),
            Paint()..color = const Color(0xFF8D9199),
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(-radius * 0.25, -radius * 0.25),
              width: radius * 1.1,
              height: radius * 0.7,
            ),
            Paint()..color = const Color(0xFFA9AEB6),
          );

        case GardenItem.flower:
          const petals = 6;
          for (var i = 0; i < petals; i++) {
            final angle = i / petals * math.pi * 2;
            canvas.drawCircle(
              Offset(math.cos(angle), math.sin(angle)) * radius * 0.75,
              radius * 0.55,
              Paint()..color = const Color(0xFFE59BB4),
            );
          }
          canvas.drawCircle(
            Offset.zero,
            radius * 0.5,
            Paint()..color = const Color(0xFFF2C55C),
          );

        case GardenItem.water:
          canvas.drawCircle(
            Offset.zero,
            radius * 1.3,
            Paint()..color = const Color(0xFF6FA8C9).withValues(alpha: 0.55),
          );
          canvas.drawCircle(
            Offset.zero,
            radius * 0.85,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = const Color(0xFF9FC9E0),
          );

        case GardenItem.grass:
          final bladePaint = Paint()
            ..color = const Color(0xFF7FA65C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round;
          for (var i = -1; i <= 1; i++) {
            final path = Path()
              ..moveTo(i * radius * 0.5, radius * 0.8)
              ..quadraticBezierTo(
                i * radius * 0.9,
                -radius * 0.2,
                i * radius * 1.3,
                -radius * 1.0,
              );
            canvas.drawPath(path, bladePaint);
          }

        case GardenItem.lantern:
          final body = Paint()..color = const Color(0xFF7E7368);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(0, radius * 0.7),
                width: radius * 1.0,
                height: radius * 1.2,
              ),
              const Radius.circular(3),
            ),
            body,
          );
          canvas.drawCircle(
            Offset(0, -radius * 0.35),
            radius * 0.75,
            Paint()..color = const Color(0xFFF0D9A0),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(0, -radius * 1.15),
                width: radius * 1.9,
                height: radius * 0.35,
              ),
              const Radius.circular(3),
            ),
            body,
          );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GardenPainter oldDelegate) =>
      oldDelegate.objects.length != objects.length || oldDelegate.sand != sand;
}
