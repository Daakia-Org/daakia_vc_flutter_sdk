import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../utils/utils.dart';

class DuplicateIdentityBottomSheet extends StatelessWidget {
  final VoidCallback onLeave;
  final VoidCallback onSwitch;
  final String? otherPlatform;

  const DuplicateIdentityBottomSheet({
    required this.onLeave,
    required this.onSwitch,
    this.otherPlatform,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.maxFinite,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          _DeviceTransferIcon(otherPlatform: otherPlatform),
          const SizedBox(height: 20),
          const Text(
            "You're already connected on\nanother device",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFD0FF)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: themeColor, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Switching devices will end your session on the other device.",
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onLeave,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: themeColor),
                    foregroundColor: themeColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Leave this meeting",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSwitch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Switch to this device",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceTransferIcon extends StatelessWidget {
  final String? otherPlatform;

  const _DeviceTransferIcon({this.otherPlatform});

  @override
  Widget build(BuildContext context) {
    final otherIcon = _iconForPlatform(otherPlatform);
    final thisIcon = _iconForPlatform(Utils.getClientPlatform());
    final otherSize = _isDesktopPlatform(otherPlatform) ? 48.0 : 40.0;
    final thisSize = _isDesktopPlatform(Utils.getClientPlatform()) ? 48.0 : 40.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(otherIcon, color: themeColor, size: otherSize),
        const SizedBox(width: 8),
        Row(
          children: List.generate(
            5,
            (i) => Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: themeColor.withAlpha(180 - i * 30),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(thisIcon, color: themeColor, size: thisSize),
      ],
    );
  }

  static IconData _iconForPlatform(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'web':
        return Icons.laptop_mac;
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
      case 'mobile_web':
        return Icons.smartphone;
      default:
        return Icons.devices;
    }
  }

  static bool _isDesktopPlatform(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'web':
      case 'macos':
      case 'windows':
      case 'linux':
        return true;
      default:
        return false;
    }
  }
}
