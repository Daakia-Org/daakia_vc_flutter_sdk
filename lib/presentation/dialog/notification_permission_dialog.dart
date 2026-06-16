import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../resources/colors/color.dart';

Future<void> showNotificationPermissionDialog(
  BuildContext context, {
  String title = 'Keep Your Meeting Alive',
  String message =
      'Allow notifications to keep your call running in the background.',
  String dismissLabel = 'Maybe Later',
}) {
  return showDialog(
    context: context,
    builder: (_) => NotificationPermissionDialog(
      title: title,
      message: message,
      dismissLabel: dismissLabel,
    ),
  );
}

class NotificationPermissionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String dismissLabel;

  const NotificationPermissionDialog({
    super.key,
    required this.title,
    required this.message,
    this.dismissLabel = 'Maybe Later',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: themeColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
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
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  openAppSettings();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Open Settings',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  dismissLabel,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
