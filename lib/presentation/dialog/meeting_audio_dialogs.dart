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

/// The host's "turn on your mic" request, while audio is disconnected here.
/// Resolves to true when the user agreed to reconnect and unmute.
Future<bool> confirmUnmuteWithAudioOff(BuildContext context) {
  return showLeaveConfirmationDialog(
    context,
    title: 'The host is asking you to unmute',
    message: 'Your audio is disconnected on this device.',
    confirmLabel: 'Reconnect audio & unmute',
    icon: Icons.mic_rounded,
    accentColor: themeColor,
    cancelLabel: 'Not now',
  );
}
