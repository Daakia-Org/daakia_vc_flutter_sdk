import 'dart:async';
import 'package:flutter/material.dart';
import '../../resources/colors/color.dart';
import '../../utils/utils.dart';

class DuplicateIdentityDialog extends StatefulWidget {
  final VoidCallback onLeave;

  const DuplicateIdentityDialog({required this.onLeave, super.key});

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
            _DeviceIcon(),
            const SizedBox(height: 20),
            const Text(
              "Joined on Another Device",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You have joined this meeting from another device. You will be disconnected from this device.",
              textAlign: TextAlign.center,
              style: TextStyle(
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
  @override
  Widget build(BuildContext context) {
    final platform = Utils.getClientPlatform();
    final icon = _iconForPlatform(platform);
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
