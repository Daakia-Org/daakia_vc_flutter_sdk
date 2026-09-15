import 'dart:async';
import 'package:daakia_vc_flutter_sdk/events/meeting_end_events.dart';
import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Tracks the meeting's scheduled end and raises the two end-of-meeting
/// warnings.
///
/// Deliberately owns no UI: it reports *when* a warning tier is due through
/// [endMeetingCallBack] and lets the meeting screen decide who sees a popup,
/// who sees a message and who hears the chime — that call needs the room
/// roster, which lives with the view model. This mirrors the web client so a
/// mixed web/mobile room warns everyone at the same moments.
///
/// Two meeting shapes, never both at once:
/// * **Normal** — one warning at [Constant.meetingEndFinalWarningTime] minutes.
/// * **Extendable / SaaS** ([isAutoMeetingEnd]) — an earlier warning at
///   [Constant.meetingEndSoonTime] minutes carrying the extend prompt, then the
///   final one. Extending is a one-shot: afterwards it behaves like a normal
///   meeting against the new end time.
class MeetingManager {
  DateTime? endDateTime;
  Timer? _checkTimer;

  /// Fires at the scheduled end once it is closer than one poll interval.
  Timer? _endTimer;
  Function(MeetingEndEvents event) endMeetingCallBack;
  bool? isAutoMeetingEnd = false;

  /// True once the meeting has been extended, locally or by a remote client.
  /// Suppresses the extend prompt for the rest of the meeting.
  bool isExtended = false;

  bool _hasEnded = false;

  MeetingManager({
    required String? endDate,
    required this.endMeetingCallBack,
    @Deprecated('No longer used; MeetingManager renders no UI of its own.')
    BuildContext? context,
    this.isAutoMeetingEnd,
  }) {
    endDateTime = _parseEndDate(endDate);
    if (endDateTime == null) {
      debugPrint(
          "Error: Invalid endDate format. Meeting scheduling will not proceed.");
    }
  }

  /// Whether the extend prompt is still on the table for this meeting.
  bool get canExtendMeeting => isAutoMeetingEnd == true && !isExtended;

  void startMeetingEndScheduler() {
    if (endDateTime == null) {
      debugPrint("Skipping scheduling due to invalid endDate.");
      return;
    }
    _checkTimer?.cancel();
    _endTimer?.cancel();
    // Polled rather than one-shot timers: extending mid-meeting, a suspended
    // app catching up, and clock drift all resolve themselves on the next tick.
    _checkTimer = Timer.periodic(
      const Duration(milliseconds: Constant.meetingEndCheckIntervalMs),
      (_) => _checkRemainingTime(),
    );
    _checkRemainingTime();
  }

  void _checkRemainingTime() {
    final endTime = endDateTime;
    if (endTime == null || _hasEnded) return;

    final Duration remaining = endTime.difference(DateTime.now());

    if (remaining <= Duration.zero) {
      _endMeeting();
      return;
    }

    // The poll alone can leave the meeting open for up to a whole interval past
    // its end — plainly visible when a live countdown has just reached zero.
    // So the final stretch also gets a one-shot timer aimed at the end itself.
    if (remaining <
        const Duration(milliseconds: Constant.meetingEndCheckIntervalMs)) {
      _endTimer?.cancel();
      _endTimer = Timer(remaining, _checkRemainingTime);
    }

    // Reported on every tick the window is open, not once on entry, so that a
    // client which becomes the extend leader partway through the window still
    // gets the prompt. The listener is responsible for showing each tier only
    // once per audience.
    if (remaining <=
        const Duration(minutes: Constant.meetingEndFinalWarningTime)) {
      endMeetingCallBack.call(MeetingEndingSoon(
        minutesRemaining: Constant.meetingEndFinalWarningTime,
        isFinalWarning: true,
      ));
      return;
    }

    // The earlier warning exists only to offer the extension, so it is skipped
    // entirely once the meeting can no longer be extended.
    if (canExtendMeeting &&
        remaining <= const Duration(minutes: Constant.meetingEndSoonTime)) {
      endMeetingCallBack.call(MeetingEndingSoon(
        minutesRemaining: Constant.meetingEndSoonTime,
        isFinalWarning: false,
      ));
    }
  }

  /// Pushes the end time out by [Constant.meetingExtendTime] minutes.
  ///
  /// Called both when this client presses Extend and when another client's
  /// extend arrives over the data channel, so it must stay idempotent-safe to
  /// call from either path.
  void extendMeetingBy10Minutes() {
    if (endDateTime == null) {
      debugPrint("Error: Cannot extend meeting. endDateTime is null.");
      return;
    }

    endDateTime =
        endDateTime!.add(const Duration(minutes: Constant.meetingExtendTime));
    isExtended = true;
    debugPrint(
        "Meeting extended by ${Constant.meetingExtendTime} minutes. New end time: $endDateTime");
    startMeetingEndScheduler();
  }

  void _endMeeting() {
    if (_hasEnded) return;
    _hasEnded = true;
    _checkTimer?.cancel();
    _endTimer?.cancel();
    endMeetingCallBack.call(MeetingEnd());
  }

  void cancelMeetingEndScheduler() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _endTimer?.cancel();
    _endTimer = null;
  }

  /// Parses whatever end-time string the backend hands over.
  ///
  /// The single `DateFormat("yyyy-MM-ddTHH:mm:ss.SSSZ")` this used to rely on
  /// returns null for anything that isn't exactly that shape — a SQL-style
  /// `2026-09-08 12:30:00`, or an ISO string without milliseconds, both parse
  /// to null, and a null end time silently disables the whole scheduler. So
  /// try the lenient ISO-8601 parser first and keep the strict format only as
  /// a fallback.
  ///
  /// A string carrying no zone (`Z` or `±HH:mm`) is read as UTC, matching the
  /// `parse(endDate, true)` the old code used.
  DateTime? _parseEndDate(String? endDate) {
    if (endDate == null || endDate.isEmpty) return null;

    final trimmed = endDate.trim();
    final hasZone = trimmed.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(trimmed);

    final iso = DateTime.tryParse(hasZone ? trimmed : '${trimmed}Z');
    if (iso != null) return iso.toLocal();

    try {
      return DateFormat("yyyy-MM-ddTHH:mm:ss.SSSZ")
          .parse(trimmed, true)
          .toLocal();
    } catch (e) {
      debugPrint("Error parsing endDate '$endDate': $e");
      return null;
    }
  }

  bool isMeetingEnded() {
    if (endDateTime == null) return false;
    return DateTime.now().isAfter(endDateTime!);
  }
}
