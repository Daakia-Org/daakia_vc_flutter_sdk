import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import 'initials_circle.dart';

class RaisedHandParticipantWidget extends StatefulWidget {
  const RaisedHandParticipantWidget({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  State<RaisedHandParticipantWidget> createState() =>
      _RaisedHandParticipantWidgetState();
}

class _RaisedHandParticipantWidgetState
    extends State<RaisedHandParticipantWidget> {
  bool isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final raisedQueue = widget.viewModel.raisedHandQueue;

    final raisedParticipants = raisedQueue
        .map((e) => widget.viewModel.getParticipantNameByIdentity(e.identity))
        .whereType<String>()
        .toList();

    if (raisedParticipants.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Raised Hands',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),

              // 🔹 Lower all button (host/cohost only)
              if (widget.viewModel.isHost() || widget.viewModel.isCoHost())
                GestureDetector(
                  onTap: () async {
                    widget.viewModel.stopHandRaisedForAll();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: const Text(
                      "Lower all",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,

        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: raisedParticipants.length,
            itemBuilder: (context, index) {
              final name = raisedParticipants[index];
              final identity = raisedQueue[index].identity;

              return Container(
                width: double.maxFinite,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
                child: Row(
                  children: [
                    InitialsCircle(
                      initials: Utils.getInitials(name),
                      size: 30,
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🔹 Raised-hand visual badge (no click)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: handRaiseColor, width: 1.2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.front_hand, color: handRaiseColor, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                "${index + 1}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 🔹 Lower button (ONLY host/cohost)
                        if (widget.viewModel.isHost() || widget.viewModel.isCoHost()) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final confirm = await showLowerHandDialog(context, name);
                              if (confirm == true) {
                                widget.viewModel.lowerHand(identity);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.redAccent, width: 1),
                              ),
                              child: const Text(
                                "Lower",
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<bool?> showLowerHandDialog(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            "Lower Hand",
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            "Are you sure you want to lower $name's hand?",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                "Lower",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}
