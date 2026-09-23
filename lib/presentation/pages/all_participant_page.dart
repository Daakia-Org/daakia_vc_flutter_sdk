import 'package:daakia_vc_flutter_sdk/presentation/widgets/invited_participant_widget.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/joined_participant_widget.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/lobby_request_widget.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/pending_attendance_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/rtc_viewmodel.dart';
import '../widgets/raised_hand_participant_widget.dart';

class AllParticipantPage extends StatelessWidget {
  const AllParticipantPage({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<RtcViewmodel>(context);
    // Landscape leaves ~150dp above the keyboard, which the app bar and
    // padding used up, hiding the search field being typed in. Drop them while
    // typing; tapping outside the field closes the keyboard and restores them.
    final media = MediaQuery.of(context);
    final isTypingInLandscape =
        media.orientation == Orientation.landscape &&
        media.viewInsets.bottom > 0;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: isTypingInLandscape
          ? null
          : AppBar(
              title: const Text(
                "Participant",
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.black,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
      // Always in the tree so the focused search field is not rebuilt, which
      // would drop focus and close the keyboard.
      body: SafeArea(
        left: false,
        right: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: isTypingInLandscape ? 4.0 : 20.0,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LobbyRequestWidget(viewModel: viewModel),
                  RaisedHandParticipantWidget(viewModel: viewModel),
                  JoinedParticipantWidget(viewModel: viewModel),
                  if (viewModel.invitedParticipantList.isNotEmpty &&
                      (viewModel.isHost() || viewModel.isCoHost()))
                    InvitedParticipantWidget(viewModel: viewModel),
                  if (viewModel.pendingParticipantList.isNotEmpty &&
                      (viewModel.isHost() || viewModel.isCoHost()))
                    PendingAttendanceWidget(viewModel: viewModel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
