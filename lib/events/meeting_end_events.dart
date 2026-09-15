abstract class MeetingEndEvents{}

class MeetingEnd extends MeetingEndEvents{}
class MeetingExtends extends MeetingEndEvents{}

/// Emitted once per warning tier as the meeting approaches its scheduled end.
///
/// [minutesRemaining] is [Constant.meetingEndSoonTime] for the early warning
/// (meant for hosts and co-hosts) or [Constant.meetingEndFinalWarningTime] for
/// the final one (for everyone). Both are raised in every meeting. The manager only decides *when* a tier is due —
/// who sees a popup, who sees a message and who hears the chime is decided by
/// the listener, which is the only place that knows the room roster.
class MeetingEndingSoon extends MeetingEndEvents {
  final int minutesRemaining;
  final bool isFinalWarning;

  MeetingEndingSoon({
    required this.minutesRemaining,
    required this.isFinalWarning,
  });
}
