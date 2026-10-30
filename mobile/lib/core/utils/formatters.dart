/// Small formatting helpers.
///
/// Written by hand rather than pulled from `intl` so the app has one fewer
/// dependency to keep in step with the Flutter SDK.
class Formatters {
  const Formatters._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// "4 Sep 2026"
  static String date(DateTime value) =>
      '${value.day} ${_months[value.month - 1]} ${value.year}';

  /// "4 Sep"
  static String shortDate(DateTime value) =>
      '${value.day} ${_months[value.month - 1]}';

  /// "Thu, 4 Sep"
  static String weekdayDate(DateTime value) =>
      '${_weekdays[value.weekday - 1]}, ${shortDate(value)}';

  /// "09:05"
  static String time(DateTime value) =>
      '${_two(value.hour)}:${_two(value.minute)}';

  /// "4 Sep 2026 at 09:05"
  static String dateTime(DateTime value) => '${date(value)} at ${time(value)}';

  /// "Today", "Yesterday", or a short date.
  static String relativeDay(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final difference = today.difference(day).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '$difference days ago';
    return shortDate(value);
  }

  /// "2:05" for a duration under an hour, otherwise "1:02:05".
  static String duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (hours > 0) return '$hours:${_two(minutes)}:${_two(seconds)}';
    return '$minutes:${_two(seconds)}';
  }

  /// "2 min 5 sec", used where a compact clock would read oddly.
  static String spokenDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    if (minutes == 0) return '$seconds sec';
    if (seconds == 0) return '$minutes min';
    return '$minutes min $seconds sec';
  }

  /// Rounds to [places] and trims a trailing ".0".
  static String number(double value, {int places = 1}) {
    final text = value.toStringAsFixed(places);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  /// "+4.2" / "-1.0" - always signed, for baseline deltas.
  static String signed(double value, {int places = 1}) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(places)}';
  }

  /// Time-of-day greeting used on the dashboard.
  static String greeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
