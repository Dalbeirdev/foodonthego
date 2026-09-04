/// Formatting for the one kind of value this module is full of: a moment in the
/// future, shown to a traveller.
///
/// Written here rather than pulled in with `intl`, because the app has no
/// localization dependency yet and adding one for four formats would be a large
/// decision made as a side effect of a small need. When the app really is
/// translated, this file is the single place that changes.
///
/// Everything takes a UTC instant and renders it in the **device's** zone. A
/// departure is a wall-clock fact to the person travelling: 6am is 6am where
/// they are standing, and showing them UTC would be correct and useless.
library;

class JourneyTime {
  const JourneyTime._();

  static const List<String> _months = <String>[
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

  static const List<String> _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// "Fri 12 Sep, 6:30 am" — the full form, for a detail screen.
  static String full(DateTime instant, {DateTime? now}) {
    final DateTime local = instant.toLocal();

    return '${relativeDay(local, now: now)}, ${time(local)}';
  }

  /// "Today", "Tomorrow", "Yesterday", or "Fri 12 Sep".
  ///
  /// The named days are worth the branch: "Tomorrow" is what somebody planning a
  /// journey is actually thinking, and a date they have to decode is friction on
  /// the screen they look at most.
  static String relativeDay(DateTime instant, {DateTime? now}) {
    final DateTime local = instant.toLocal();
    final DateTime today = _midnight((now ?? DateTime.now()).toLocal());
    final int days = _midnight(local).difference(today).inDays;

    return switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => date(local),
    };
  }

  /// "Fri 12 Sep", or "Fri 12 Sep 2027" when the year is not the current one.
  ///
  /// Dropping the year for the current one keeps the common case short; keeping
  /// it for any other prevents a journey planned across New Year from reading as
  /// though it were days away.
  static String date(DateTime instant, {DateTime? now}) {
    final DateTime local = instant.toLocal();
    final int thisYear = (now ?? DateTime.now()).toLocal().year;

    final String base =
        '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}';

    return local.year == thisYear ? base : '$base ${local.year}';
  }

  /// "6:30 am". Twelve-hour with a lower-case suffix, matching the launch market.
  static String time(DateTime instant) {
    final DateTime local = instant.toLocal();
    final int hour24 = local.hour;
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String minute = local.minute.toString().padLeft(2, '0');

    return '$hour12:$minute ${hour24 < 12 ? 'am' : 'pm'}';
  }

  /// "Fri 12 Sep · 6:30 am", for a list row where the two halves need separating.
  static String compact(DateTime instant, {DateTime? now}) {
    final DateTime local = instant.toLocal();

    return '${relativeDay(local, now: now)} · ${time(local)}';
  }

  /// Combines a picked date with a picked time into one instant.
  ///
  /// The pickers hand back two independent values, and doing this by hand at
  /// each call site is how a form ends up with a departure on the right day at
  /// midnight.
  static DateTime combine(DateTime day, int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  static DateTime _midnight(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
