import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';

/// Asks a host or co-host to confirm sending [name] back to the lobby.
/// Resolves to true when they confirm.
Future<bool> showMoveToLobbyDialog(
  BuildContext context, {
  required String name,
  bool useCallTerminology = false,
}) async {
  final noun = useCallTerminology ? 'call' : 'meeting';
  // A double tap would pop twice, closing whatever is under the dialog.
  var closed = false;
  void close(BuildContext dialogContext, bool result) {
    if (closed) return;
    closed = true;
    Navigator.of(dialogContext).pop(result);
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _LobbyCard(
      icon: Icons.meeting_room_outlined,
      iconColor: themeColor,
      title: 'Move to lobby?',
      message: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            TextSpan(
              text: ' will leave the $noun and wait in the lobby until '
                  'someone admits them again.',
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: _messageStyle,
      ),
      actions: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => close(dialogContext, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: const BorderSide(color: Colors.black26),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _primaryButton(
            label: 'Move',
            onPressed: () => close(dialogContext, true),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

const _messageStyle = TextStyle(
  fontSize: 14,
  color: Colors.black54,
  height: 1.5,
);

Widget _primaryButton({required String label, required VoidCallback onPressed}) {
  return ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: themeColor,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    ),
  );
}

/// The card layout of `DuplicateIdentityDialog`: tinted icon, title, message,
/// full-width buttons.
class _LobbyCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget message;
  final List<Widget> actions;

  const _LobbyCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(24),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 34),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          message,
        ],
      ),
      actions: [Row(children: actions)],
    );
  }
}
