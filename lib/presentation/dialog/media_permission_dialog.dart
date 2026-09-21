import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../resources/colors/color.dart';

/// The device permissions the pre-join screen asks for.
enum MediaPermission {
  microphone(
    label: 'Microphone',
    icon: Icons.mic_rounded,
    reason: 'so others in the meeting can hear you',
  ),
  camera(
    label: 'Camera',
    icon: Icons.videocam_rounded,
    reason: 'so others in the meeting can see you',
  );

  const MediaPermission({
    required this.label,
    required this.icon,
    required this.reason,
  });

  final String label;
  final IconData icon;
  final String reason;

  Permission get permission => this == MediaPermission.microphone
      ? Permission.microphone
      : Permission.camera;
}

/// Explains a denied [permission] and offers the way back to granting it:
/// asking again, or — once the system won't ask anymore
/// ([permanentlyDenied]) — opening the app's settings. Resolves to true if the
/// permission ends up granted from inside the dialog.
Future<bool> showMediaPermissionDialog(
  BuildContext context,
  MediaPermission permission, {
  required bool permanentlyDenied,
}) async {
  final granted = await showDialog<bool>(
    context: context,
    builder: (_) => MediaPermissionDialog(
      permission: permission,
      permanentlyDenied: permanentlyDenied,
    ),
  );
  return granted ?? false;
}

class MediaPermissionDialog extends StatefulWidget {
  const MediaPermissionDialog({
    super.key,
    required this.permission,
    required this.permanentlyDenied,
  });

  final MediaPermission permission;
  final bool permanentlyDenied;

  @override
  State<MediaPermissionDialog> createState() => _MediaPermissionDialogState();
}

class _MediaPermissionDialogState extends State<MediaPermissionDialog> {
  // Can flip to true while open: denying the re-ask again can make Android
  // stop asking, and then only Settings can grant it.
  late bool _permanentlyDenied = widget.permanentlyDenied;
  bool _requesting = false;

  Future<void> _allow() async {
    if (_permanentlyDenied) {
      await openAppSettings();
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    setState(() => _requesting = true);
    final status = await widget.permission.permission.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _requesting = false;
      _permanentlyDenied = status.isPermanentlyDenied;
    });
  }

  @override
  Widget build(BuildContext context) {
    final permission = widget.permission;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final title = _permanentlyDenied
        ? '${permission.label} access is off'
        : '${permission.label} access needed';
    // No product name: the SDK runs inside host apps with their own branding.
    final message = _permanentlyDenied
        ? '${permission.label} access is turned off for this app. Turn it on '
            'in Settings ${permission.reason}.'
        : 'Allow ${permission.label.toLowerCase()} access '
            '${permission.reason}.';

    final allowButton = FilledButton(
      onPressed: _requesting ? null : _allow,
      style: FilledButton.styleFrom(
        backgroundColor: themeColor,
        disabledBackgroundColor: themeColor.withValues(alpha: 0.6),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _requesting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(_permanentlyDenied ? 'Open Settings' : 'Allow'),
    );
    final notNowButton = TextButton(
      onPressed: () => Navigator.of(context).pop(false),
      style: TextButton.styleFrom(
        foregroundColor: Colors.black54,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text('Not now'),
    );

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 440 : 400),
        // Safety net for short landscape screens and large text scales.
        child: SingleChildScrollView(
          padding: isLandscape
              ? const EdgeInsets.fromLTRB(24, 20, 24, 16)
              : const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PermissionIcon(
                icon: permission.icon,
                blocked: _permanentlyDenied,
                size: isLandscape ? 48 : 64,
              ),
              SizedBox(height: isLandscape ? 12 : 16),
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
              SizedBox(height: isLandscape ? 16 : 24),
              // Side by side in landscape to save height; stacked in portrait
              // with the primary action on top.
              if (isLandscape)
                Row(
                  children: [
                    Expanded(child: notNowButton),
                    const SizedBox(width: 12),
                    Expanded(child: allowButton),
                  ],
                )
              else ...[
                SizedBox(width: double.infinity, child: allowButton),
                const SizedBox(height: 4),
                SizedBox(width: double.infinity, child: notNowButton),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The permission's icon in a tinted circle, with a small "blocked" badge
/// once it can only be re-enabled from Settings.
class _PermissionIcon extends StatelessWidget {
  const _PermissionIcon({
    required this.icon,
    required this.blocked,
    required this.size,
  });

  final IconData icon;
  final bool blocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.38;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: themeColor, size: size * 0.5),
          ),
          if (blocked)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.block_rounded,
                  color: Colors.white,
                  size: badgeSize * 0.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
