/// Turning metres and seconds into something a person reads.
///
/// The conversion lives here, at the edge, and nowhere else. Everything from the
/// provider through to the widget carries integers: a value that becomes
/// "278 km" early cannot be shown in miles, cannot be summed with a second leg,
/// and cannot be re-rendered when the app learns a second language.
class JourneyMeasures {
  const JourneyMeasures._();

  /// "278 km", "4.2 km", "850 m".
  ///
  /// Metres below a kilometre, because "0.85 km" is a number a person has to
  /// convert in their head. One decimal place under ten kilometres, because the
  /// difference between 4.2 and 4.7 is a junction; none above, because nobody
  /// plans a 278 km drive around 400 metres.
  static String distance(int metres) {
    if (metres < 1000) {
      return '$metres m';
    }

    final double kilometres = metres / 1000;

    if (kilometres < 10) {
      return '${kilometres.toStringAsFixed(1)} km';
    }

    return '${kilometres.round()} km';
  }

  /// "4 hr 32 min", "45 min", "1 min".
  ///
  /// Rounded to the nearest minute and never to "0 min": a journey that exists
  /// takes at least a minute, and a zero would read as an error rather than as
  /// a very short drive.
  static String duration(int seconds) {
    final int totalMinutes = (seconds / 60).round();

    if (totalMinutes < 1) {
      return '1 min';
    }

    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;

    if (hours == 0) {
      return '$minutes min';
    }

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }

  /// "+12 min", or null when there is nothing honest to say.
  ///
  /// Null for an absent traffic reading **and** for a delay under a minute: a
  /// "+0 min" badge is a claim about the roads dressed up as a measurement, and
  /// a rounded-away thirty seconds is not congestion.
  static String? trafficDelay(int? delaySeconds) {
    if (delaySeconds == null || delaySeconds < 60) {
      return null;
    }

    return '+${duration(delaySeconds)}';
  }

  /// How this route compares with the recommended one: "12 km shorter",
  /// "12 min longer", or null when the difference is not worth a line.
  ///
  /// Thresholds rather than any difference at all, because "1 min longer" on a
  /// four-hour drive is noise the provider itself would not stand behind.
  static String? comparison({
    required int metres,
    required int seconds,
    required int againstMetres,
    required int againstSeconds,
  }) {
    final int metreDelta = metres - againstMetres;
    final int secondDelta = seconds - againstSeconds;

    if (secondDelta.abs() >= 120) {
      final String amount = duration(secondDelta.abs());
      return secondDelta > 0 ? '$amount longer' : '$amount quicker';
    }

    if (metreDelta.abs() >= 1000) {
      final String amount = distance(metreDelta.abs());
      return metreDelta > 0 ? '$amount further' : '$amount shorter';
    }

    return null;
  }

  /// "Calculated just now", "Calculated 6 minutes ago".
  ///
  /// Shown next to a traffic figure so nobody reads a fifteen-minute-old
  /// estimate as live. Never claims to be current, because nothing is
  /// refreshing it.
  static String calculatedAgo(DateTime calculatedAt, {DateTime? now}) {
    final Duration elapsed = (now ?? DateTime.now().toUtc()).toUtc().difference(
      calculatedAt.toUtc(),
    );

    if (elapsed.inMinutes < 1) {
      return 'Calculated just now';
    }

    if (elapsed.inMinutes < 60) {
      final int minutes = elapsed.inMinutes;
      return 'Calculated $minutes ${minutes == 1 ? "minute" : "minutes"} ago';
    }

    final int hours = elapsed.inHours;

    if (hours < 24) {
      return 'Calculated $hours ${hours == 1 ? "hour" : "hours"} ago';
    }

    final int days = elapsed.inDays;

    return 'Calculated $days ${days == 1 ? "day" : "days"} ago';
  }
}
