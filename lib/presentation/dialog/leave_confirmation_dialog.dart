import 'package:flutter/material.dart';

/// Asks before leaving or ending the meeting.
///
/// Resolves to true only when [confirmLabel] is tapped; Cancel, Back and a tap
/// outside all resolve to false.
Future<bool> showLeaveConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.call_end_rounded,
  Color accentColor = LeaveConfirmationDialog.danger,
  String cancelLabel = 'Cancel',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => LeaveConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      accentColor: accentColor,
      cancelLabel: cancelLabel,
    ),
  );
  return confirmed == true;
}

/// Leaving the meeting (participant, or a host who lets it run on).
Future<bool> confirmLeaveMeeting(BuildContext context,
    {bool useCallTerminology = false}) {
  final session = useCallTerminology ? 'call' : 'meeting';
  return showLeaveConfirmationDialog(
    context,
    title: 'Leave the $session?',
    message: 'You can rejoin while the $session is still going.',
    confirmLabel: 'Leave $session',
  );
}

/// Ending the meeting for everyone (host or co-host).
Future<bool> confirmEndMeetingForAll(BuildContext context,
    {bool useCallTerminology = false}) {
  final session = useCallTerminology ? 'call' : 'meeting';
  return showLeaveConfirmationDialog(
    context,
    title: 'End the $session for everyone?',
    message: 'Everyone will be disconnected and the $session will close. '
        'This can’t be undone.',
    confirmLabel: 'End $session for all',
    icon: Icons.groups_rounded,
  );
}

class LeaveConfirmationDialog extends StatelessWidget {
  const LeaveConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.icon = Icons.call_end_rounded,
    this.accentColor = danger,
    this.cancelLabel = 'Cancel',
  });

  final String title;
  final String message;
  final String confirmLabel;
  final IconData icon;

  /// Icon tint and confirm button; red unless the action isn't destructive.
  final Color accentColor;
  final String cancelLabel;

  static const Color danger = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Same clamp as the other SDK cards: a landscape phone is only ~360dp
    // tall, so the content scrolls rather than pushing the buttons off.
    final maxHeight = media.size.height - media.viewInsets.vertical - 96;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight.clamp(160.0, 560.0),
          minWidth: 280,
          maxWidth: 360,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 30),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(foregroundColor: Colors.black54),
                  child: Text(cancelLabel,
                      style: const TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
