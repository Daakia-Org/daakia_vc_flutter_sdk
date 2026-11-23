import 'package:daakia_vc_flutter_sdk/presentation/widgets/compact_participant_tile.dart';
import 'package:flutter/material.dart';

import '../../viewmodel/rtc_viewmodel.dart';

class PendingAttendanceWidget extends StatefulWidget {
  const PendingAttendanceWidget({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  State<PendingAttendanceWidget> createState() =>
      _PendingAttendanceWidgetState();
}

class _PendingAttendanceWidgetState extends State<PendingAttendanceWidget> {
  bool isExpanded = false; // Track if the list is expanded

  @override
  Widget build(BuildContext context) {
    // A sliver: the participants page builds rows only as they scroll in.
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Inactive Participants',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    isExpanded = !isExpanded; // Toggle list visibility
                  });
                },
                icon: Icon(
                  isExpanded
                      ? Icons.arrow_drop_down_sharp
                      : Icons.arrow_right_sharp,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (isExpanded)
          SliverList.builder(
            itemCount: widget.viewModel.pendingParticipantList.length,
            itemBuilder: (context, index) {
              var participant = widget.viewModel.pendingParticipantList[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: CompactParticipantTile(name: participant.screenName),
              );
            },
          ),
      ],
    );
  }
}
