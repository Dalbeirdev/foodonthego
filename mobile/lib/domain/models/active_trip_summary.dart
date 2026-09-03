/// A journey in progress, as the home screen needs it.
///
/// The fields Module 05 and Module 09 will populate are declared now — progress,
/// distance, next pickup — so the card that renders them does not have to be
/// redesigned when the data arrives. What is *not* here is anything that implies
/// a route calculation has happened: this model carries results, never inputs to
/// a map API.
class ActiveTripSummary {
  const ActiveTripSummary({
    required this.id,
    required this.originLabel,
    required this.destinationLabel,
    required this.status,
    this.estimatedDuration,
    this.remainingDuration,
    this.totalDistanceKm,
    this.progress,
    this.nextPickupLabel,
  });

  final String id;
  final String originLabel;
  final String destinationLabel;
  final TripStatus status;

  final Duration? estimatedDuration;
  final Duration? remainingDuration;
  final double? totalDistanceKm;

  /// 0.0–1.0 along the route. Null until Module 09 can compute it.
  final double? progress;

  final String? nextPickupLabel;

  /// Clamped, because a progress value slightly outside the range — a rounding
  /// artefact from a future ETA service — must not paint a bar past its track.
  double? get clampedProgress => progress?.clamp(0.0, 1.0);
}

enum TripStatus {
  planned,
  onTheRoad,
  arrived,
  completed,
  cancelled;

  String get label => switch (this) {
    TripStatus.planned => 'Planned',
    TripStatus.onTheRoad => 'On the road',
    TripStatus.arrived => 'Arrived',
    TripStatus.completed => 'Completed',
    TripStatus.cancelled => 'Cancelled',
  };

  bool get isActive =>
      this == TripStatus.planned || this == TripStatus.onTheRoad;
}
