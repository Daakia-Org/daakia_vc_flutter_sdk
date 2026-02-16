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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Participant", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LobbyRequestWidget(viewModel: viewModel),
                RaisedHandParticipantWidget(viewModel: viewModel),
                JoinedParticipantWidget(viewModel: viewModel),
                if (viewModel.pendingParticipantList.isNotEmpty &&
                    (viewModel.isHost() || viewModel.isCoHost()))
                  PendingAttendanceWidget(viewModel: viewModel)
              ],
            ),
          ),
        ),
      ),
    );
  }
}
