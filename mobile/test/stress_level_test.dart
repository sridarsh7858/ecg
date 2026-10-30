import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';

void main() {
  group('StressLevel', () {
    test('numbers run 1 to 5 in order', () {
      expect(StressLevel.values.map((level) => level.number), [1, 2, 3, 4, 5]);
    });

    test('fromNumber maps every valid number', () {
      for (var number = 1; number <= 5; number++) {
        expect(StressLevel.fromNumber(number).number, number);
      }
    });

    test('fromNumber clamps out-of-range values instead of throwing', () {
      expect(StressLevel.fromNumber(0), StressLevel.veryLow);
      expect(StressLevel.fromNumber(-4), StressLevel.veryLow);
      expect(StressLevel.fromNumber(6), StressLevel.veryHigh);
      expect(StressLevel.fromNumber(99), StressLevel.veryHigh);
    });

    test('previous and next stay inside the scale', () {
      expect(StressLevel.veryLow.previous, StressLevel.veryLow);
      expect(StressLevel.veryHigh.next, StressLevel.veryHigh);
      expect(StressLevel.moderate.previous, StressLevel.low);
      expect(StressLevel.moderate.next, StressLevel.high);
    });
  });

  group('StressLevelConfig', () {
    test('every level has an entry', () {
      for (final level in StressLevel.values) {
        expect(StressLevelConfig.of(level).level, level);
      }
      expect(StressLevelConfig.all.length, 5);
    });

    test('titles match the project definition', () {
      expect(StressLevelConfig.ofNumber(1).title, 'Very Low');
      expect(StressLevelConfig.ofNumber(2).title, 'Low');
      expect(StressLevelConfig.ofNumber(3).title, 'Moderate');
      expect(StressLevelConfig.ofNumber(4).title, 'High');
      expect(StressLevelConfig.ofNumber(5).title, 'Very High');
    });

    test('every level carries complete, non-empty copy', () {
      for (final info in StressLevelConfig.all) {
        expect(info.title, isNotEmpty);
        expect(info.description, isNotEmpty);
        expect(info.recommendation, isNotEmpty);
        expect(info.motivation, isNotEmpty);
        expect(info.suggestedGameIds, isNotEmpty);
      }
    });

    test('upperTitle and levelLabel format for display', () {
      final info = StressLevelConfig.ofNumber(3);
      expect(info.upperTitle, 'MODERATE');
      expect(info.levelLabel, 'Level 3');
    });

    test('copy avoids alarming medical language', () {
      const banned = ['disease', 'diagnos', 'danger', 'illness', 'disorder'];
      for (final info in StressLevelConfig.all) {
        final text =
            '${info.description} ${info.recommendation} ${info.motivation}'
                .toLowerCase();
        for (final word in banned) {
          expect(text.contains(word), isFalse, reason: 'level ${info.number}');
        }
      }
    });

    test('light and dark accents differ, for contrast in both themes', () {
      for (final info in StressLevelConfig.all) {
        expect(info.lightColor, isNot(info.darkColor));
      }
    });
  });
}
