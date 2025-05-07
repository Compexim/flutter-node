// lib/activity_filter_utils.dart

enum ActivityFilterStatus { all, active, inactive }

String statusToString(ActivityFilterStatus status) {
  switch (status) {
    case ActivityFilterStatus.active:
      return 'Aktív';
    case ActivityFilterStatus.inactive:
      return 'Nem aktív';
    case ActivityFilterStatus.all:
    default:
      return 'Mindegyik';
  }
}

String activityFilterStatusToQueryParam(ActivityFilterStatus status) {
  switch (status) {
    case ActivityFilterStatus.active:
      return 'true';
    case ActivityFilterStatus.inactive:
      return 'false';
    case ActivityFilterStatus.all:
    default:
      return ''; // Backend kezeli, ha üres, akkor nincs szűrés erre
  }
}
