/// What the meeting screen hands back to the pre-join screen when a host or
/// co-host has sent this participant back to the lobby.
///
/// The server has already created the lobby request, so the pre-join screen
/// waits on [requestId] instead of asking to join again. [micOn] / [cameraOn]
/// are what the participant had in the meeting, so the wait keeps them.
class MovedToLobby {
  final String requestId;
  final bool micOn;
  final bool cameraOn;

  const MovedToLobby({
    required this.requestId,
    required this.micOn,
    required this.cameraOn,
  });
}
