import 'dart:async';
import 'package:flutter/material.dart';
import '../../resources/colors/color.dart';
import '../../utils/utils.dart';

/// Shown when the server ends this device's session with DUPLICATE_IDENTITY.
///
/// The default copy is for a real join from another device. Use
/// [DuplicateIdentityDialog.connectionDropped] when the kick came from this
/// device's own reconnect (see `_onDuplicateIdentity` in room.dart), so the
/// user isn't told about a device they never used.
class DuplicateIdentityDialog extends StatefulWidget {
  final VoidCallback onLeave;
  final String title;
  final String message;

  /// Null shows the icon for this device's platform.
  final IconData? icon;

  const DuplicateIdentityDialog({
    required this.onLeave,
    this.title = "Joined on Another Device",
    this.message =
        "You have joined this meeting from another device. You will be disconnected from this device.",
    this.icon,
    super.key,
  });

  const DuplicateIdentityDialog.connectionDropped({
    required VoidCallback onLeave,
    Key? key,
  }) : this(
          onLeave: onLeave,
          title: "Connection Lost",
          message:
              "Your internet connection dropped and you were disconnected from this meeting. Please rejoin once your connection is stable.",
          icon: Icons.wifi_off_rounded,
          key: key,
        );

  @override
  State<DuplicateIdentityDialog> createState() =>
      _DuplicateIdentityDialogState();
}

class _DuplicateIdentityDialogState extends State<DuplicateIdentityDialog> {
  int _countdown = 5;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        widget.onLeave();
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DeviceIcon(icon: widget.icon),
            const SizedBox(height: 20),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.maxFinite,
            child: ElevatedButton(
              onPressed: widget.onLeave,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                "Leave Meeting ($_countdown)",
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceIcon extends StatelessWidget {
  final IconData? icon;

  const _DeviceIcon({this.icon});

  @override
  Widget build(BuildContext context) {
    final platform = Utils.getClientPlatform();
    final icon = this.icon ?? _iconForPlatform(platform);
    final iconSize = _isDesktop(platform) ? 40.0 : 36.0;

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: themeColor.withAlpha(20),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: themeColor, size: iconSize),
    );
  }

  static IconData _iconForPlatform(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'web':
      case 'macos':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.desktop_windows_outlined;
      case 'linux':
        return Icons.computer_outlined;
      case 'android':
        return Icons.smartphone;
      case 'ios':
        return Icons.phone_iphone;
      default:
        return Icons.devices;
    }
  }

  static bool _isDesktop(String? platform) {
    return ['web', 'macos', 'windows', 'linux']
        .contains(platform?.toLowerCase());
  }
}
