import 'package:flutter/material.dart';

import '../../utils/utils.dart';

/// Small colored label for one role a participant holds.
class RolePill extends StatelessWidget {
  const RolePill({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Every role label the participant behind [metadata] holds. The meeting role
/// (Host/Co-Host) and the guest flag are independent — a guest promoted to
/// co-host carries both — so this returns a list rather than picking one.
/// Lay it out with a [Wrap] so the labels drop to another line instead of
/// being clipped.
List<Widget> buildRolePills(String? metadata) {
  return [
    if (Utils.isHost(metadata))
      const RolePill(label: "Host", color: Colors.amberAccent),
    if (Utils.isCoHost(metadata))
      const RolePill(label: "Co-Host", color: Colors.lightBlueAccent),
    if (Utils.isGuest(metadata))
      const RolePill(label: "Guest", color: Colors.greenAccent),
  ];
}
