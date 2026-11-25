import 'package:livekit_client/livekit_client.dart';

abstract class RTCEvents{}

class ShowSnackBar extends RTCEvents {
  final String message;
  ShowSnackBar(this.message);
}

class ShowTranscriptionDownload extends RTCEvents {
  final String message;
  final String? path;
  ShowTranscriptionDownload({required this.message, required this.path});
}
class ShowReaction extends RTCEvents{
  final String emoji;
  ShowReaction(this.emoji);
}

class OpenPrivateChat extends RTCEvents{
  final Participant? participant;
  OpenPrivateChat(this.participant);
}

class ShowProgress extends RTCEvents{
  final double progress;
  ShowProgress(this.progress);
}

class WhiteboardStatus extends RTCEvents{
  final bool status;
  WhiteboardStatus({required this.status});
}

class ShowLoading extends RTCEvents{}

class StopLoading extends RTCEvents{}

class UpdateView extends RTCEvents{}

class EnterPIP extends RTCEvents{}

class SortParticipants extends RTCEvents{}

/// Host-control state has just been loaded, so whatever Workshop restrictions
/// are already in force can be announced — this is how someone joining a
/// meeting that's *already* in Workshop mode gets told, since they never see
/// the actions that turned it on.
class ShowWorkshopModeNotice extends RTCEvents{}

class EndMeeting extends RTCEvents{
  final String reason;
  EndMeeting({required this.reason});
}