import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../model/meeting_details_model.dart';

/// When a meeting really ends, reconciled from the two end times the backend
/// sends in `meeting/basic/detail`.
///
/// * `end_date` — the **scheduled** end, in real UTC. The extend API never
///   moves it.
/// * `meeting_config.auto_meeting_end_schedule` — the end **including any
///   extension**, but written as the meeting's local wall-clock time with a
///   `Z` stuck on the end. Observed 2026-09-15 for an Asia/Kolkata meeting
///   extended by 10 minutes: `end_date=10:54:05Z` unchanged, while the schedule
///   went `16:24:05Z` -> `16:34:05Z`, i.e. 11:04:05 UTC.
///
/// The wall-clock reading is converted through the meeting's own IANA zone
/// (`timezone_identifier`), daylight saving included, so every device lands on
/// the same instant whatever its own timezone. The later of the two wins — an
/// extension only ever moves the end out — and if the schedule can't be
/// converted, `end_date` stands alone.
class MeetingEndTime {
  const MeetingEndTime._({this.scheduled, this.extended});

  /// `end_date`, in UTC.
  final DateTime? scheduled;

  /// `auto_meeting_end_schedule` converted to UTC through the meeting's zone.
  final DateTime? extended;

  factory MeetingEndTime.from(MeetingDetailsModel? details) {
    return MeetingEndTime._(
      scheduled: _parseUtc(details?.endDate),
      extended: _wallClockToUtc(
        details?.meetingConfig?.autoMeetingEndSchedule,
        details?.timezoneIdentifier,
      ),
    );
  }

  /// The instant the meeting ends, in UTC.
  DateTime? get end {
    final scheduled = this.scheduled;
    final extended = this.extended;
    if (scheduled == null) return extended;
    if (extended == null) return scheduled;
    return extended.isAfter(scheduled) ? extended : scheduled;
  }

  /// ISO-8601 with no zone is read as UTC, as `end_date` always has been.
  static DateTime? _parseUtc(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    final parsed =
        DateTime.tryParse(_hasZone(trimmed) ? trimmed : '${trimmed}Z');
    return parsed?.toUtc();
  }

  static DateTime? _wallClockToUtc(String? value, String? zoneId) {
    if (value == null || value.trim().isEmpty) return null;
    final location = _location(zoneId);
    if (location == null) return null;

    // Drop the misleading zone suffix and keep only the wall-clock fields.
    final trimmed = value.trim();
    final naive = _hasZone(trimmed)
        ? trimmed.replaceFirst(_zoneSuffix, '')
        : trimmed;
    final wall = DateTime.tryParse(naive);
    if (wall == null) return null;

    final local = tz.TZDateTime(location, wall.year, wall.month, wall.day,
        wall.hour, wall.minute, wall.second, wall.millisecond);
    return DateTime.fromMillisecondsSinceEpoch(local.millisecondsSinceEpoch,
        isUtc: true);
  }

  static final RegExp _zoneSuffix = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  static bool _hasZone(String value) => _zoneSuffix.hasMatch(value);

  static bool _zonesLoaded = false;

  static tz.Location? _location(String? zoneId) {
    if (zoneId == null || zoneId.trim().isEmpty) return null;
    if (!_zonesLoaded) {
      tz_data.initializeTimeZones();
      _zonesLoaded = true;
    }
    try {
      return tz.getLocation(zoneId.trim());
    } catch (_) {
      return null;
    }
  }
}
