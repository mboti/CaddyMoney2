enum SupportRequestStatus {
  newRequest,
  inProgress,
  resolved;

  String toJson() => switch (this) {
        SupportRequestStatus.newRequest => 'new',
        SupportRequestStatus.inProgress => 'in_progress',
        SupportRequestStatus.resolved => 'resolved',
      };

  static SupportRequestStatus fromJson(dynamic v) {
    final s = v?.toString().trim().toLowerCase();
    return switch (s) {
      'in_progress' || 'in progress' || 'inprogress' => SupportRequestStatus.inProgress,
      'resolved' => SupportRequestStatus.resolved,
      _ => SupportRequestStatus.newRequest,
    };
  }

  String get displayName => switch (this) {
        SupportRequestStatus.newRequest => 'New',
        SupportRequestStatus.inProgress => 'In progress',
        SupportRequestStatus.resolved => 'Resolved',
      };
}
