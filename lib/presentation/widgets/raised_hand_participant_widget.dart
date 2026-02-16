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
  @override
  Widget build(BuildContext context) {
    /// 🔹 Get raised-hand queue (already ordered)
    final raisedQueue = widget.viewModel.raisedHandQueue;

    /// 🔹 Convert to participant models
    final raisedParticipants = raisedQueue
        .map((e) => widget.viewModel.getParticipantNameByIdentity(e.identity))
        .whereType() // remove nulls safely
        .toList();

    /// 🔹 Hide widget if nobody raised hand
    if (raisedParticipants.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Raised Hands',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),

        /// 📋 Raised-hand list (ordered)
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: raisedParticipants.length,
          itemBuilder: (context, index) {
            final name = raisedParticipants[index];

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: handRaiseColor,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.front_hand,
                          color: handRaiseColor,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${index + 1}",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
