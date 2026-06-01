import 'package:daakia_vc_flutter_sdk/presentation/widgets/participant_tile.dart';
import 'package:flutter/material.dart';

import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../dialog/pariticipant_dialog_controls.dart';

class JoinedParticipantWidget extends StatefulWidget {
  const JoinedParticipantWidget({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  State<JoinedParticipantWidget> createState() =>
      _JoinedParticipantWidgetState();
}

class _JoinedParticipantWidgetState extends State<JoinedParticipantWidget> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final allParticipants = widget.viewModel.getParticipantList();
    final filteredParticipants = allParticipants.where((participant) {
      final name = participant.participant.name.toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Participants (${allParticipants.length})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (Utils.isHost(
                    widget.viewModel.room.localParticipant?.metadata) ||
                Utils.isCoHost(
                    widget.viewModel.room.localParticipant?.metadata))
              IconButton(
                onPressed: () {
                  showParticipantDialog(context, widget.viewModel);
                },
                icon: const Icon(
                  Icons.more_vert,
                  color: Colors.white,
                ),
              ),
          ],
        ),
        // 🔍 Search Field
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search participant...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (query) {
              setState(() {
                _searchQuery = query;
              });
            },
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredParticipants.length,
          itemBuilder: (context, index) {
            var participant = filteredParticipants[index];
            return ParticipantTile(
              participant: participant.participant,
              isForLobby: false,
              onDismissBottomSheet: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            );
          },
        ),
      ],
    );
  }

  void showParticipantDialog(BuildContext context, RtcViewmodel viewModel) {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return ParticipantDialogControls(
            participant: viewModel.participant,
            viewModel: viewModel,
            isForIndividual: false,
          );
        });
  }
}
