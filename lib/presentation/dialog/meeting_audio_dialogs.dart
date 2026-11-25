import 'package:daakia_vc_flutter_sdk/presentation/dialog/leave_confirmation_dialog.dart';
import 'package:daakia_vc_flutter_sdk/resources/colors/color.dart';
import 'package:flutter/material.dart';

/// Asks before disconnecting audio on this device, so nobody does it by
/// accident and then wonders why they can't hear anyone.
Future<bool> confirmDisconnectAudio(BuildContext context) {
  return showLeaveConfirmationDialog(
    context,
    title: 'Disconnect Audio?',
    message: "You won't hear anyone, and no one will hear you. Use this when "
        'another device in the room is already in the meeting.',
    confirmLabel: 'Disconnect',
    icon: Icons.headset_off_rounded,
    accentColor: themeColor,
  );
}

/// Shown when a disabled mic or speaker button is tapped while audio is
/// disconnected. Resolves to true when the user chose to reconnect.
Future<bool> showAudioDisconnectedPrompt(BuildContext context) {
  return showLeaveConfirmationDialog(
    context,
    title: 'Audio disconnected',
    message: "On this device you can't hear anyone, and no one can hear you.",
    confirmLabel: 'Reconnect audio',
    icon: Icons.headset_off_rounded,
    accentColor: themeColor,
    cancelLabel: 'Keep disconnected',
  );
}

/// A host's or co-host's "turn on your mic" request, while audio is
/// disconnected here. [requesterName] is who asked, when known.
/// Resolves to true when the user agreed to reconnect and unmute.
Future<bool> confirmUnmuteWithAudioOff(
  BuildContext context, {
  String? requesterName,
}) {
  return showLeaveConfirmationDialog(
    context,
    title: '${askerLabel(requesterName)} is asking you to turn on your mic',
    message: 'Your audio is disconnected on this device. Reconnect it to '
        'unmute.',
    confirmLabel: 'Reconnect & unmute',
    icon: Icons.mic_rounded,
    accentColor: themeColor,
    cancelLabel: 'Not now',
  );
}

/// Workshop mode: a host or co-host allowed the mic while audio is
/// disconnected here, so the user can't be heard yet. A dialog rather than a
/// toast, because a toast is missed on another page (chat, participants).
/// Resolves to true when the user chose to reconnect and unmute.
Future<bool> confirmMicGrantedWithAudioOff(BuildContext context) {
  return showLeaveConfirmationDialog(
    context,
    title: 'You can now use your mic',
    message: 'Your audio is disconnected on this device. Reconnect it to '
        'unmute.',
    confirmLabel: 'Reconnect & unmute',
    icon: Icons.mic_rounded,
    accentColor: themeColor,
    cancelLabel: 'Not now',
  );
}

/// Names who sent a request, falling back to "The host" when the sender's
/// name isn't known.
String askerLabel(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? 'The host' : trimmed;
}
